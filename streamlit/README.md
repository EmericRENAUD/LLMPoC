# Interface Streamlit pour un LLM servi par vLLM

Chat Streamlit (réponses en streaming) qui appelle l'API OpenAI-compatible d'un serveur vLLM déjà déployé.

```
Navigateur ──> Ingress ──> Service streamlit ──> Service vllm (/v1)
```

## Configuration (variables d'environnement)

| Variable | Défaut | Rôle |
|---|---|---|
| `VLLM_BASE_URL` | `http://vllm:8000/v1` | URL de l'API vLLM (adapter au nom du Service / namespace, ex. `http://vllm.mon-ns.svc:8000/v1`) |
| `MODEL_NAME` | `llm` | Doit correspondre à `--served-model-name` côté vLLM (ou au nom du modèle) |
| `VLLM_API_KEY` | `EMPTY` | Clé API si vLLM est lancé avec `--api-key` (à mettre dans un Secret) |

## Test local

```bash
kubectl port-forward svc/vllm 8000:8000 &
cd app
pip install -r requirements.txt
VLLM_BASE_URL=http://localhost:8000/v1 MODEL_NAME=llm streamlit run app.py
```

## Déploiement

```bash
docker build -t registry.example.com/streamlit-chat:0.1.0 app/
docker push registry.example.com/streamlit-chat:0.1.0

# adapter l'image, les variables d'environnement et le host de l'Ingress
kubectl apply -f k8s/streamlit.yaml

# sans Ingress :
kubectl port-forward svc/streamlit 8501:80   # http://localhost:8501
```

## Notes

- Un seul réplica au départ : l'historique de conversation est stocké dans la session Streamlit côté serveur, donc des sticky sessions sont nécessaires si vous scalez.
- L'Ingress a des timeouts longs (WebSockets + streaming) ; l'annotation fournie vise ingress-nginx, à adapter pour un autre contrôleur.
