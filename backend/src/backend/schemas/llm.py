from typing import Any, Dict, List, Literal, Optional
from pydantic import BaseModel, Field


class LLMConfig(BaseModel):
    base_url: str = Field(
        default="https://openrouter.ai/api/v1",
        description="OpenRouter or any OpenAI-compatible API base URL",
    )
    api_key: str = Field(
        default="",
        description="API Key for OpenRouter or OpenAI-compatible provider",
    )
    model: str = Field(
        default="anthropic/claude-3.5-sonnet",
        description="Model ID (e.g. anthropic/claude-3.5-sonnet, openai/gpt-4o, deepseek/deepseek-chat)",
    )
    temperature: float = Field(default=0.2, ge=0.0, le=2.0)
    max_tokens: Optional[int] = Field(default=4096)


class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant", "tool"]
    content: Optional[str] = None
    name: Optional[str] = None
    tool_call_id: Optional[str] = None
    tool_calls: Optional[List[Dict[str, Any]]] = None


class ChatTaskRequest(BaseModel):
    project_path: str = Field(description="Target project directory root on host PC")
    messages: List[ChatMessage] = Field(description="Conversation message history")
    llm_config: LLMConfig = Field(description="LLM provider and model configuration")
    max_steps: int = Field(default=10, description="Max agentic tool-calling turns")


class ModelInfo(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    context_length: Optional[int] = None
    pricing: Optional[Dict[str, Any]] = None


class FetchModelsRequest(BaseModel):
    base_url: str = Field(default="https://openrouter.ai/api/v1")
    api_key: str = Field(default="")


class FetchModelsResponse(BaseModel):
    models: List[ModelInfo]
    count: int


class TokenUsage(BaseModel):
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0
    reasoning_tokens: int = 0
    cached_tokens: int = 0
    cost: float | None = None
    context_tokens: int = 0
    exact: bool = True


class StreamEvent(BaseModel):
    type: Literal[
        "status",
        "chunk",
        "tool_call_start",
        "tool_call_result",
        "usage",
        "done",
        "error",
    ]
    content: Optional[str] = None
    tool: Optional[str] = None
    args: Optional[Dict[str, Any]] = None
    output: Optional[str] = None
    message: Optional[str] = None
    total_steps: Optional[int] = None
    usage: Optional[TokenUsage] = None
