# Alternativas locais ao Ollama

Estas ferramentas rodam modelos de IA no próprio computador, sem enviar dados para a nuvem.  
Todas são gratuitas e open-source. Use-as como complemento ou substituto do Ollama.

---

## 1. Open WebUI

Interface web para conversar com modelos Ollama (ou OpenAI-compatible) via navegador.

| Item | Detalhe |
|------|---------|
| Site | https://github.com/open-webui/open-webui |
| Pré-requisito | Ollama rodando em `localhost:11434` |
| Instalação rápida | `docker run -d -p 3000:80 --add-host=host.docker.internal:host-gateway -v open-webui:/app/backend/data --name open-webui ghcr.io/open-webui/open-webui:main` |
| Acesso | http://localhost:3000 |

**O que faz:**
- Interface tipo ChatGPT no navegador
- Suporte a multimodal (imagens) com modelos compatíveis
- Histórico de conversas, pastas e compartilhamento local
- Permite selecionar modelos Ollama sem usar o terminal

**Como evitar cloud involuntário:** na tela de configurações do Open WebUI, certifique-se de que a URL da API aponta para `http://localhost:11434` e **não** para `api.ollama.com`.

---

## 2. llama.cpp

Motor de inferência em C++ para rodar modelos GGUF diretamente, sem o daemon do Ollama.

| Item | Detalhe |
|------|---------|
| Site | https://github.com/ggml-org/llama.cpp |
| Formato de modelo | GGUF (encontre em https://huggingface.co) |
| GPU | CUDA, Metal, Vulkan, ROCm |

**Instalação (macOS/Linux):**
```bash
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build && cmake --build build --config Release -j
# Com suporte CUDA: cmake -B build -DGGML_CUDA=ON
```

**Uso básico:**
```bash
# Inferência em modo texto
./build/bin/llama-cli -m modelo.gguf -p "Olá, como vai?" -n 200

# Servidor HTTP compatível com API OpenAI
./build/bin/llama-server -m modelo.gguf --port 8080
```

**Quando usar em vez do Ollama:**
- Precisar de controle fino de quantização (q4_K_M, q8_0, etc.)
- Testar modelos GGUF antes de criar um Modelfile Ollama
- Hardware muito limitado (pode rodar sem GPU)

---

## 3. whisper.cpp

Transcrição de áudio local (Speech-to-Text) usando o modelo Whisper da OpenAI, sem enviar áudio para a nuvem.

| Item | Detalhe |
|------|---------|
| Site | https://github.com/ggml-org/whisper.cpp |
| Modelos | tiny, base, small, medium, large-v3 |
| GPU | Metal (Apple), CUDA, OpenCL |

**Instalação (macOS/Linux):**
```bash
git clone https://github.com/ggml-org/whisper.cpp
cd whisper.cpp
cmake -B build && cmake --build build -j
# Baixar modelo (ex: small em português):
bash ./models/download-ggml-model.sh small
```

**Transcrição de um arquivo de áudio:**
```bash
./build/bin/whisper-cli -m models/ggml-small.bin -l pt -f audio.wav
```

**Integração com este projeto (postagem-automatica):**  
Futuramente, o whisper.cpp pode ser usado para transcrever áudios do WhatsApp e gerar posts a partir de conteúdo falado, sem expor o áudio a servidores externos.

---

## Comparativo rápido

| Ferramenta | Propósito principal | Dificuldade | GPU necessária |
|---|---|---|---|
| Ollama | Chat e geração de texto | Fácil | Não (melhora desempenho) |
| Open WebUI | Interface web para Ollama | Fácil (Docker) | Não |
| llama.cpp | Inferência direta de GGUF | Média | Não (mas recomendada) |
| whisper.cpp | Transcrição de áudio | Média | Não (mas recomendada) |

---

## Escolhendo o modelo certo para seu hardware

| Perfil | RAM livre | Modelo recomendado |
|--------|-----------|-------------------|
| Leve | 4–6 GB | `qwen3:4b`, `gemma3:4b` |
| Intermediário | 8–12 GB | `qwen3:8b`, `deepseek-r1:8b` |
| Mais pesado | 16 GB+ | `qwen3.5:9b` ou maior |

> Regra geral: o modelo precisa caber inteiro na VRAM (GPU) para rodar rápido.  
> Se não couber, o Ollama usa RAM + disco, o que é muito mais lento.
