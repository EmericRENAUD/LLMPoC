# LLMPoC
Petit POC de test de déploiement de LLM

# Prérequis
- Docker installé
- Kubernetes installé
- k9s (optionnel)
- Avoir un cluster local minikube à disposition.
- Aovir un compte hugginface avec un TOKEN et les authorisations d'accès au modèle meta-llama/Llama-3.2-1B-Instruct

# Déploiement:
1) Insérez le token Hugging face dans le fichier [vLLM.yaml](vLLM/vLLM.yaml) ici:
```
apiVersion: v1
kind: Secret
metadata:
  name: hf-token-secret
type: Opaque
stringData:
  token: "REPLACE_WITH_TOKEN"  <==== ICI
```

2) Déployez le serveur d'inférence vLLM
```
kubectl apply -f vLLM/vLLM.yaml
```
Soyez patient, le démarrage peut prendre quelques minutes.

3) Construisez l'image docker utile pour streamlit:
```
cd streamlit/app
docker build . -t my-streamlit
```

4) Montez l'image "my-streamlit" dans le node
```
minikube image load my-streamlit:latest
```

5) Déployez streamlit
```
kubectl apply -f streamlit/k8s/streamlit.yaml
```

6) Exposez le service de streamlit
```
kubectl port-forward svc/streamlit 8501:8501
```

7) Connectez vous à l'interface streamlit sur votre navigateur via l'url
```
http://localhost:8501
```

Et enjoy la petite discussion.
/!\ Le modèle déployé est un petit modèle qui fonctionne avec votre CPU. Ne vous attendez pas à un traitement rapide de vos questions et à des réponses qualitative. Ce modèle hallucine souvent et n'est déployé qu'à des fin de petit test de déploiement.