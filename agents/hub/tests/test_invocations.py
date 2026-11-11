from __future__ import annotations

import asyncio
import json
import os
import unittest
from unittest.mock import AsyncMock, Mock, patch

# main builds its dependencies at import time; keep tests independent of a local .env.
os.environ.setdefault("SERVICE_PROJECT_ENDPOINT", "https://example.services.ai.azure.com/api/projects/test")
os.environ.setdefault("SERVICE_MODEL_DEPLOYMENT", "test-model")

import httpx
from agent_framework import AgentResponse, Content, Message

import main
from hub_agent import HubAgent
from models.query_response import QueryResponse
from services.agent_invoker import AgentInvoker


async def _updates(*contents):
    for content in contents:
        yield Mock(contents=[content])


class InvocationTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.classifier = Mock()
        self.classifier.run = AsyncMock(
            return_value=AgentResponse(
                messages=[Message("assistant", [Content.from_text('{"target_agent":"card-agent"}')])]
            )
        )
        with patch("hub_agent.AgentInvoker") as invoker_class:
            self.hub = HubAgent(self.classifier)
            self.invoker = invoker_class.return_value
        self.invoker.get_agent_registry.return_value = ["card-agent"]
        self.invoker.invoke_stream = Mock(side_effect=self.domain_stream)

    async def domain_stream(self, **kwargs):
        for chunk in ("Your card ", "is active."):
            yield chunk
        yield QueryResponse(
            response="Your card is active.",
            session_id="voice-session",
            agent="card-agent",
            tool_results=[{"status": "active"}],
        )

    async def events(self, payload, session_id="voice-session"):
        return [event async for event in self.hub.process_event(payload, session_id)]

    async def test_voice_and_text_input_shapes_route_clean_text(self) -> None:
        payloads = [
            {"type": "input_audio.transcription", "input": "Check my card"},
            {"input": "Check my card"},
            {"type": "response.create", "text": "Check my card"},
            {"type": "response.create", "response": {"invoke_input": {"text": "Check my card"}}},
            {"type": "response.create", "response": {"invokeInput": {"input": "Check my card"}}},
            {"query": "Check my card", "session_id": "untrusted"},
            {"input": json.dumps({"query": "Check my card", "session_id": "untrusted"})},
        ]
        for payload in payloads:
            with self.subTest(payload=payload):
                events = await self.events(payload)
                self.assertEqual(
                    [event["type"] for event in events],
                    [
                        "hubagent.conversation",
                        "output_audio_transcription.delta",
                        "output_audio_transcription.delta",
                        "output_audio_transcription.done",
                        "hubagent.metadata",
                        "done",
                    ],
                )
                self.assertEqual([events[1]["delta"], events[2]["delta"]], ["Your card ", "is active."])
                self.assertEqual(events[3]["text"], "Your card is active.")
                self.assertEqual(events[4]["data"]["tool_results"], [{"status": "active"}])
                self.assertNotIn("response", events[4]["data"])
                request = self.invoker.invoke_stream.call_args.kwargs["request"]
                self.assertEqual(request.query, "Check my card")
                self.assertEqual(request.session_id, "voice-session")

    async def test_history_and_context_reach_routing(self) -> None:
        await self.events({"input": "First turn"})
        await self.events(
            {"response": {"invoke_input": {"text": "Second turn", "context": {"channel": "web"}}}}
        )
        history = self.invoker.invoke_stream.call_args.kwargs["history"]
        self.assertEqual([message.text for message in history], ["First turn", "Your card is active."])
        self.assertEqual(self.invoker.invoke_stream.call_args.kwargs["request"].context, {"channel": "web"})
        await self.events({"input": "Other session"}, "other-session")
        self.assertEqual(self.invoker.invoke_stream.call_args.kwargs["history"], [])

    async def test_bind_and_interruption_are_silent_and_session_scoped(self) -> None:
        await self.events({"input": "Check my card"})
        bind = {"action": "assistant_item_bind", "assistantItem": {"itemId": "item-1"}}
        wrapped = {"type": "response.create", "response": {"invokeInput": bind}}
        self.assertEqual(await self.events(wrapped), [{"type": "done"}])
        self.assertEqual(await self.events({"input": json.dumps(bind)}), [{"type": "done"}])
        interruption = {"itemId": "item-1", "spokenChars": 4, "totalChars": 20, "elapsedMs": 950}
        self.assertEqual(
            await self.events({"text": json.dumps({"action": "interruption", "interruption": interruption})}),
            [{"type": "done"}],
        )
        assistant = self.hub._history["voice-session"][-1]
        self.assertEqual(assistant.additional_properties["voice_live_item_id"], "item-1")
        self.assertEqual(assistant.additional_properties["interruption"], interruption)
        rejected = await self.events(
            {"action": "interruption", "interruption": interruption}, "other-session"
        )
        self.assertEqual(rejected[0]["type"], "hubagent.event.rejected")
        self.invoker.invoke_stream.assert_called_once()

    async def test_invalid_events_reject_without_routing_and_finish(self) -> None:
        for payload in (
            {"type": "unsupported", "input": "hello"},
            {"input": " "},
            {"input": '{"query": false}'},
            {"response": {"invoke_input": []}},
            {"action": "unknown"},
            {"action": "assistant_item_bind", "assistantItem": {}},
        ):
            with self.subTest(payload=payload):
                events = await self.events(payload)
                self.assertEqual(events[0]["type"], "hubagent.event.rejected")
                self.assertEqual(events[-1], {"type": "done"})
        self.invoker.invoke_stream.assert_not_called()

    async def test_http_sse_session_affinity_and_invocations_only(self) -> None:
        with patch.object(main, "_hub_agent", self.hub):
            await self._assert_http_contract()

    async def _assert_http_contract(self) -> None:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=main.app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/invocations?agent_session_id=voice-session",
                json={"type": "input_audio.transcription", "input": "Check my card"},
            )
            self.assertEqual(response.status_code, 200)
            self.assertTrue(response.headers["content-type"].startswith("text/event-stream"))
            self.assertEqual(response.headers["x-agent-session-id"], "voice-session")
            frames = [
                json.loads(frame.removeprefix("data: "))
                for frame in response.text.strip().split("\n\n")
            ]
            self.assertEqual([frames[1]["delta"], frames[2]["delta"]], ["Your card ", "is active."])
            self.assertEqual(frames[-1], {"type": "done"})
            for body in ("not json", "[]"):
                rejected = await client.post("/invocations", content=body)
                self.assertEqual(rejected.status_code, 400)
                self.assertEqual(rejected.json()["type"], "hubagent.event.rejected")
            self.assertEqual((await client.post("/responses", json={})).status_code, 404)
            self.assertEqual((await client.get("/invocations_ws")).status_code, 404)

    async def test_framework_run_still_returns_query_response(self) -> None:
        result = await self.hub.run('{"query":"Check my card","session_id":"framework-session"}')
        payload = json.loads(result.text)
        self.assertEqual(payload["response"], "Your card is active.")
        self.assertEqual(payload["session_id"], "framework-session")

    async def test_chunks_are_forwarded_before_domain_stream_completes(self) -> None:
        release = asyncio.Event()

        async def gated_stream(**kwargs):
            yield "First part. "
            await release.wait()
            yield "Second part."
            yield QueryResponse(response="", session_id="voice-session", agent="card-agent")

        self.invoker.invoke_stream = Mock(side_effect=gated_stream)
        events = self.hub.process_event({"input": "Check my card"}, "voice-session")
        self.assertEqual((await anext(events))["type"], "hubagent.conversation")
        first = await asyncio.wait_for(anext(events), timeout=1)
        self.assertEqual(first, {"type": "output_audio_transcription.delta", "delta": "First part. "})
        release.set()
        rest = [event async for event in events]
        self.assertEqual(rest[0]["delta"], "Second part.")
        self.assertEqual(rest[1]["text"], "First part. Second part.")

    async def test_interrupted_stream_keeps_spoken_text(self) -> None:
        async def failing_stream(**kwargs):
            yield "Partial answer"
            raise RuntimeError("connection reset")

        self.invoker.invoke_stream = Mock(side_effect=failing_stream)
        events = await self.events({"input": "Check my card"})
        self.assertEqual(
            [event["type"] for event in events],
            [
                "hubagent.conversation",
                "output_audio_transcription.delta",
                "output_audio_transcription.done",
                "hubagent.metadata",
                "done",
            ],
        )
        self.assertEqual(events[2]["text"], "Partial answer")
        self.assertEqual(self.hub._history["voice-session"][-1].text, "Partial answer")


class DomainStreamParsingTests(unittest.IsolatedAsyncioTestCase):
    async def collect(self, *contents):
        return [
            item
            async for item in AgentInvoker.consume_stream(
                _updates(*contents), agent_name="card-agent", session_id="s1", timeout_seconds=30
            )
        ]

    async def test_text_is_streamed_and_reasoning_metadata_stays_out_of_speech(self) -> None:
        metadata = {
            "domain_metadata": {
                "agent": "card-agent",
                "confidence": "high",
                "tool_results": [{"status": "active"}],
                "token_usage": {"input_tokens": 5, "output_tokens": 7, "total_tokens": 12},
            }
        }
        items = await self.collect(
            Content.from_text("Your card "),
            Content.from_text("is active."),
            Content.from_text_reasoning(text=json.dumps(metadata)),
        )
        self.assertEqual(items[:2], ["Your card ", "is active."])
        final = items[2]
        self.assertIsInstance(final, QueryResponse)
        self.assertEqual(final.response, "Your card is active.")
        self.assertEqual(final.tool_results, [{"status": "active"}])
        self.assertEqual(final.token_usage["total_tokens"], 12)

    async def test_legacy_json_reply_is_never_spoken_verbatim(self) -> None:
        legacy = json.dumps({"response": "Your card is active.", "session_id": "s1", "agent": "card-agent"})
        items = await self.collect(Content.from_text(legacy[:20]), Content.from_text(legacy[20:]))
        self.assertEqual(items[0], "Your card is active.")
        self.assertEqual(items[1].agent, "card-agent")
        self.assertEqual(len(items), 2)


if __name__ == "__main__":
    unittest.main()
