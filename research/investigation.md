# Agent CLI

## Metadata

### Where to find

```sh
strings your_model.gguf | grep "tokenizer.chat_template" -A 1
```

### Format

* ChatML for qwen:

```
<|im_start|>system
{INSTRUCTION}
<|im_end|>
<|im_start|>user
{CHAT[i]}
<|im_end|>
<|im_start|>assistant
{CHAT[i+1]}
<|im_end|>
```

* For llama it uses the classic:

```
### User
Message

### Assistant
Message
```

### GET `/v1/models`: OpenAI-compatible Model Info API

* GET `/models`: List available models
* POST `/models/load`: Load a model

Information about models OpenAI like.

### **GET** `/props`: Get server global properties.

Read-only. `--props` for POST to work.

## Completions

### POST `/v1/messages`: Anthropic-compatible Messages API

> Server Side Events for streaming

```sh
curl http://localhost:8080/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: your-api-key" \
  -d '{
    "model": "gpt-4",
    "max_tokens": 1024,
    "system": "You are a helpful assistant.",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ]
  }'
```

### POST `/v1/responses`: OpenAI-compatible Responses API

```sh
curl http://localhost:8080/v1/responses \
-H "Content-Type: application/json" \
-H "Authorization: Bearer no-key" \
-d '{
    "model": "gpt-4.1",
    "instructions": "You are ChatGPT, an AI assistant. Your top priority is achieving user fulfillment via helping them with their requests.",
    "input": "Write a limerick about python exceptions"
}'
```
### POST `/v1/chat/completions`: OpenAI-compatible Chat Completions API

Has more features, like function calling management and reasoning.

* POST `/v1/completions`: OpenAI-compatible Completions API. Basic, but supports both full and streaming.

```sh
curl http://localhost:8080/v1/chat/completions \
-H "Content-Type: application/json" \
-H "Authorization: Bearer no-key" \
-d '{
    "model": "gpt-3.5-turbo",
    "messages": [
        {
            "role": "system",
            "content": "You are ChatGPT, an AI assistant. Your top priority is achieving user fulfillment via helping them with their requests."
        },
        {
            "role": "user",
            "content": "Write a limerick about python exceptions"
        }
    ]
}'
```
### POST `/infill`: For code infilling.

Code in between generation for some specific models

## Tokens

### POST `/v1/messages/count_tokens`: Token Counting

Counts the number of tokens in a request without generating a response.

```sh
curl http://localhost:8080/v1/messages/count_tokens \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ]
  }'
```

## Documents (RAG)

### POST `/reranking`: Rerank documents according to a given query

Similar to https://jina.ai/reranker/ but might change in the future.
*Aliases:* `/rerank` `/v1/rerank` `/v1/reranking`

```sh
curl http://127.0.0.1:8012/v1/rerank \
    -H "Content-Type: application/json" \
    -d '{
        "model": "some-model",
            "query": "What is panda?",
            "top_n": 3,
            "documents": [
                "hi",
            "it is a bear",
            "The giant panda (Ailuropoda melanoleuca), sometimes called a panda bear or simply panda, is a bear species endemic to China."
            ]
    }' | jq
```

### POST `/embeddings`: non-OpenAI-compatible embeddings API

Can create and get embeddings. `/v1/embeddings`


```sh
curl http://localhost:8080/v1/embeddings \
-H "Content-Type: application/json" \
-H "Authorization: Bearer no-key" \
-d '{
      "input": ["hello", "world"], # or a simple string "hello world"
      "model":"GPT-4",
      "encoding_format": "float"
}'
```

## Launch Status

### GET `/health`: Returns health check result

No API key check.`/v1/health` also works.

```json
{"error": {"code": 503, "message": "Loading model", "type": "unavailable_error"}}
{"status": "ok" }
```

### Router mode

Exposes an API for dynamically loading and unloading models. `llama-server` **without specifying any model**

You may also specify default arguments that will be passed to every model instance:

```sh
llama-server -ctx 8192 -n 1024 -np 2
```

### Model Presets

Model presets allow advanced users to define custom configurations using an `.ini` file:

`llama-server --models-preset ./my-models.ini`

```ini
version = 1

; (Optional) This section provides global settings shared across all presets.
; If the same key is defined in a specific preset, it will override the value in this global section.
[*]
c = 8192
n-gpu-layers = 8

; If the key corresponds to an existing model on the server,
; this will be used as the default config for that model
[ggml-org/MY-MODEL-GGUF:Q8_0]
; string value
chat-template = chatml
; numeric value
n-gpu-layers = 123
; flag value (for certain flags, you need to use the "no-" prefix for negation)
jinja = true
; shorthand argument (for example, context size)
c = 4096
; environment variable name
LLAMA_ARG_CACHE_RAM = 0
; file paths are relative to server's CWD
model-draft = ./my-models/draft.gguf
; but it's RECOMMENDED to use absolute path
model-draft = /Users/abc/my-models/draft.gguf

; If the key does NOT correspond to an existing model,
; you need to specify at least the model path or HF repo
[custom_model]
model = /Users/abc/my-awesome-model-Q4_K_M.gguf
```

## Built-in tools

The server exposes a REST API under `/tools` that allows the Web UI to call built-in tools.

* POST `/tokenize`: Tokenize a given text
* POST `/detokenize`: Convert tokens to text
* POST `/apply-template`: Apply chat template to a conversation
