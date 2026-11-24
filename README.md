# LLMPoC
Petit POC de test de déploiement de LLM

# Prérequis
- Docker installé
- Kubernetes installé
- Helm installé
- minikube installé
- k9s (optionnel)
- Avoir un cluster local minikube à disposition.
- Aovir un compte hugginface avec un TOKEN et les authorisations d'accès au modèle meta-llama/Llama-3.2-1B-Instruct

# Déploiement vLLM standard:
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


# Déploiement vLLM via kServe en serverless:
1) Déployer un cluster minikube et y installer kserve:
```
cd kServe
./kServe-minikube.sh install
```

2) Pull localement l'image de vllm cpu, la retag et la monter dans le cluster minikube:
```
docker image pull public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:v0.11.2 
docker tag public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:v0.11.2 dev.local/vllm-cpu:v0.11.2
minikube image load dev.local/vllm-cpu:v0.11.2 -p kserve
```

3) Build l'image streamlit et la monter dans le cluster minikube:
```
cd streamlit/app
docker build . -t my-streamlit
minikube image load my-streamlit:latest -p kserve
```

4) Mettre votre token HF dans le manifeste du secret [ici](kServe/vLLM.yaml)
```
# --------- Secret ------------------------------
apiVersion: v1
kind: Secret
metadata:
  name: hf-secret
type: Opaque
stringData:
  HF_TOKEN: "REPLACE_WITH_TOKEN" <========== ICI
```

5) Appliquer le manifeste vLLM.yaml du dossier kServe 
```
kubectl apply -f kServe/vLLM.yaml
```

Le déploiement doit prendre un peu de temps soyez patient.
Au final vous devriez avoir quelque chose comme ça:

```
NAME                                                           READY   STATUS    RESTARTS   AGE
pod/llama-3-2-1b-predictor-00001-deployment-86b9c849ff-fdspl   2/2     Running   0          26m

NAME                                           TYPE           CLUSTER-IP      EXTERNAL-IP                                            PORT(S)                                     AGE
service/kubernetes                             ClusterIP      10.96.0.1       <none>                                                 443/TCP                                     19h
service/llama-3-2-1b                           ExternalName   <none>          knative-local-gateway.istio-system.svc.cluster.local   <none>                                      26m
service/llama-3-2-1b-predictor                 ExternalName   <none>          knative-local-gateway.istio-system.svc.cluster.local   80/TCP                                      19m
service/llama-3-2-1b-predictor-00001           ClusterIP      10.100.0.213    <none>                                                 80/TCP,443/TCP                              26m
service/llama-3-2-1b-predictor-00001-private   ClusterIP      10.102.17.58    <none>                                                 80/TCP,443/TCP,9090/TCP,9091/TCP,8012/TCP   26m

NAME                                                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/llama-3-2-1b-predictor-00001-deployment   1/1     1            1           26m

NAME                                                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/llama-3-2-1b-predictor-00001-deployment-86b9c849ff   1         1         1       26m

NAME                                                       LATESTCREATED                  LATESTREADY                    READY   REASON
configuration.serving.knative.dev/llama-3-2-1b-predictor   llama-3-2-1b-predictor-00001   llama-3-2-1b-predictor-00001   True    

NAME                                                        CONFIG NAME              GENERATION   READY   REASON   ACTUAL REPLICAS   DESIRED REPLICAS
revision.serving.knative.dev/llama-3-2-1b-predictor-00001   llama-3-2-1b-predictor   1            True             1                 1

NAME                                               URL                                                 READY   REASON
route.serving.knative.dev/llama-3-2-1b-predictor   http://llama-3-2-1b-predictor.default.example.com   True    

NAME                                                 URL                                                 LATESTCREATED                  LATESTREADY                    READY   REASON
service.serving.knative.dev/llama-3-2-1b-predictor   http://llama-3-2-1b-predictor.default.example.com   llama-3-2-1b-predictor-00001   llama-3-2-1b-predictor-00001   True    
```

6) Appliquez le manifeste streamlit de kServe:
```
kubectl apply -f kServe/streamlit.yaml
```

7) Exposez streamlit:
```
kubectl port-forward svc/streamlit 8501:80
```

8) Discutez avec le llm déployé en ouvrant l'adresse suivante dans votre navigateur préféré:
```
http://localhost:8501
```
# Exposition du modèle avec vérification par clef API via kong et hashicorp vault
## Installation de vault (minimale)
1) Installer hashicorp vault:
```
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install vault hashicorp/vault -n vault --create-namespace \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=root" \
  --set "injector.enabled=true"
```

Le pod vault-0 démarre déjà unsealed, avec le root token root. Rien à initialiser.

2) Exporter les variables d'environnement suivantes:
```
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root
```

3) Exposer le vault sur le port 8200:
```
kubectl port-forward -n vault svc/vault 8200:8200
```

4) Verifier que le vault fonctionne:
```
vault status
```
## Installation de External Secret
5) Installer External Secret Operator:
```
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --set installCRDs=true
```

6) Préparer une clef api dans le vault:
```
kubectl exec -n vault vault-0 -- sh -c '
export VAULT_TOKEN=root
vault secrets enable -path=secret kv-v2 || true
vault kv put secret/kong/alice key=ma-super-api-key
'
```

7) Donner à ESO l'accès au Vault (un token suffit pour le POC):
Monter les creds du vault dans un secret
```
kubectl create secret generic vault-token -n external-secrets \
  --from-literal=token=root
```

