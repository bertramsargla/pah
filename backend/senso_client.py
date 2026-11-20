"""Thin wrapper around the Senso Context Layer REST API.

Docs: https://docs.senso.ai/docs/quickstart and https://docs.senso.ai/docs/shared-context-quickstart
Base URL: https://apiv2.senso.ai/api/v1
Auth: header X-API-Key: <key>
"""

import os
import time

import httpx

BASE_URL = "https://apiv2.senso.ai/api/v1"


class SensoError(RuntimeError):
    pass


class SensoClient:
    def __init__(self, api_key: str | None = None, timeout: float = 30.0):
        self.api_key = api_key or os.environ.get("SENSO_API_KEY")
        if not self.api_key:
            raise SensoError("SENSO_API_KEY is not set")
        self._client = httpx.Client(
            base_url=BASE_URL,
            headers={"X-API-Key": self.api_key, "Content-Type": "application/json"},
            timeout=timeout,
        )

    def close(self):
        self._client.close()

    def _request(self, method: str, path: str, **kwargs):
        resp = self._client.request(method, path, **kwargs)
        if resp.status_code == 202 and path.startswith("/org/evals"):
            return resp.json()
        if resp.status_code >= 400:
            raise SensoError(f"{method} {path} -> {resp.status_code}: {resp.text}")
        return resp.json()

    def whoami(self) -> dict:
        """GET /org/me - verify the key and see org id / free-tier status."""
        return self._request("GET", "/org/me")

    def upsert_brand_kit(self, brand_name: str, brand_description: str | None = None) -> dict:
        """PUT /org/brand-kit - tell Senso what "your brand" means.

        Required for POST /org/evals/text to actually score claims: the judge
        only checks claims it can tie to your organization (about_brand=true).
        Without a brand kit naming your fictional retailer, every claim about
        it comes back about_brand=false / passed=null (silently un-scored).
        """
        guidelines = {"brand_name": brand_name}
        if brand_description:
            guidelines["brand_description"] = brand_description
        return self._request("PUT", "/org/brand-kit", json={"guidelines": guidelines})

    def ingest_raw(self, title: str, text: str) -> dict:
        """POST /org/kb/raw - add a text/markdown document to the knowledge base.

        Returns immediately (202) with id, kb_node_id, type, title, processing_status.
        Duplicate text for the org returns 409.
        """
        return self._request("POST", "/org/kb/raw", json={"title": title, "text": text})

    def get_node(self, kb_node_id: str) -> dict:
        """GET /org/kb/nodes/{kb_node_id} - check processing status of an ingested doc."""
        return self._request("GET", f"/org/kb/nodes/{kb_node_id}")

    def wait_for_processing(self, kb_node_id: str, poll_seconds: float = 5.0, max_wait: float = 120.0) -> dict:
        elapsed = 0.0
        while elapsed < max_wait:
            node = self.get_node(kb_node_id)
            status = (node.get("content") or {}).get("processing_status")
            if status == "complete":
                return node
            if status == "failed":
                raise SensoError(f"Ingestion failed for {kb_node_id}: {node}")
            time.sleep(poll_seconds)
            elapsed += poll_seconds
        raise SensoError(f"Timed out waiting for {kb_node_id} to finish processing")

    def search(self, query: str) -> dict:
        """POST /org/search - RAG endpoint: Senso writes the answer.

        Returns {query, answer, results: [{content_id, title, chunk_text, score, rank}], total_results}
        """
        return self._request("POST", "/org/search", json={"query": query})

    def search_context(self, query: str) -> dict:
        """POST /org/search/context - returns retrieved chunks only, no answer.

        Use this when your own model should write the answer, with full citation
        fields for the audit trail: content_chunk_id, content_id, kb_node_id,
        version_id, chunk_index, chunk_text, score, rank, inclusion_reason,
        source_type, retrieval{...}.
        """
        return self._request("POST", "/org/search/context", json={"query": query})

    def check_text(
        self,
        text: str,
        author: str,
        question: str | None = None,
        wait: bool = True,
    ) -> dict:
        """POST /org/evals/text - fact-check a claim-bearing text against the KB.

        author: "ai_assistant" for the agent's own answers, "organization" for
        content you wrote yourself (e.g. a product description).
        question: the shopper's original request, improves claim matching.
        wait=True returns the finished check inline if done within ~60s,
        otherwise returns {eval_run_id} to poll via get_eval_run.
        Uses no Senso credits. Skips text starting with "I'm sorry"/"I can't".
        """
        payload = {"text": text, "author": author, "wait": wait}
        if question:
            payload["question"] = question
        # Senso holds a waiting check open for up to about a minute.
        return self._request("POST", "/org/evals/text", json=payload, timeout=120.0)

    def get_eval_run(self, eval_run_id: str) -> dict:
        """GET /org/evals/runs/{eval_run_id} - poll a fact-check that didn't finish inline."""
        return self._request("GET", f"/org/evals/runs/{eval_run_id}")

    def wait_for_eval(self, eval_run_id: str, poll_seconds: float = 10.0, max_wait: float = 90.0) -> dict:
        elapsed = 0.0
        while elapsed < max_wait:
            run = self.get_eval_run(eval_run_id)
            if run.get("status") == "completed":
                return run
            time.sleep(poll_seconds)
            elapsed += poll_seconds
        raise SensoError(f"Timed out waiting for eval run {eval_run_id}")
