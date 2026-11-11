from __future__ import annotations

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
        self.invoker.invoke = AsyncMock(
            return_value=QueryResponse(
                response="Your card is active.",
                session_id="voice-session",
                agent="card-agent",
                tool_results=[{"status": "active"}],
            )
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
                        "output_audio_transcription.done",
                        "hubagent.metadata",
                        "done",
                    ],
                )
                self.assertEqual(events[1]["delta"], "Your card is active.")
                self.assertEqual(events[2]["text"], "Your card is active.")
                self.assertEqual(events[3]["data"]["tool_results"], [{"status": "active"}])
                self.assertNotIn("response", events[3]["data"])
                request = self.invoker.invoke.call_args.kwargs["request"]
                self.assertEqual(request.query, "Check my card")
                self.assertEqual(request.session_id, "voice-session")

    async def test_history_and_context_reach_routing(self) -> None:
        await self.events({"input": "First turn"})
        await self.events(
            {"response": {"invoke_input": {"text": "Second turn", "context": {"channel": "web"}}}}
        )
        history = self.invoker.invoke.call_args.kwargs["history"]
        self.assertEqual([message.text for message in history], ["First turn", "Your card is active."])
        self.assertEqual(self.invoker.invoke.call_args.kwargs["request"].context, {"channel": "web"})
        await self.events({"input": "Other session"}, "other-session")
        self.assertEqual(self.invoker.invoke.call_args.kwargs["history"], [])

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
        self.invoker.invoke.assert_awaited_once()

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
        self.invoker.invoke.assert_not_awaited()

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
            self.assertEqual(frames[1]["delta"], "Your card is active.")
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


if __name__ == "__main__":
    unittest.main()
