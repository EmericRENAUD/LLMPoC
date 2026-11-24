#!/usr/bin/env bash
# Déploie KServe (mode serverless / Knative) sur un minikube local.
#
# Usage :
#   ./kserve-minikube.sh install     # démarre minikube + installe KServe et ses dépendances
#   ./kserve-minikube.sh test        # déploie un modèle Llama de test et une interface streamlit exposée
#   ./kserve-minikube.sh close       # supprime les déploiements de tests
#   ./kserve-minikube.sh uninstall   # désinstalle KServe et ses dépendances
#   ./kserve-minikube.sh delete      # supprime le cluster minikube
#
# Variables surchargeables : KSERVE_VERSION, MINIKUBE_PROFILE, MINIKUBE_CPUS,
# MINIKUBE_MEMORY, MINIKUBE_DISK, MINIKUBE_DRIVER, K8S_VERSION

set -euo pipefail

KSERVE_VERSION="${KSERVE_VERSION:-v0.18.0}"
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-kserve}"
MINIKUBE_CPUS="${MINIKUBE_CPUS:-6}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-12288}"   # en Mo. Prévoir plus pour des LLMs (16+ Go)
MINIKUBE_DISK="${MINIKUBE_DISK:-60g}"
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-docker}"
K8S_VERSION="${K8S_VERSION:-}"                # vide = version par défaut de minikube

BASE_URL="https://github.com/kserve/kserve/releases/download/${KSERVE_VERSION}"
INSTALL_SCRIPT_URL="${BASE_URL}/kserve-knative-mode-full-install-with-manifests.sh"
KCTX="${MINIKUBE_PROFILE}"

check_tools() {
  local missing=()
  for t in minikube kubectl curl helm; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if ((${#missing[@]})); then
    echo "Outils manquants : ${missing[*]}" >&2
    exit 1
  fi
  # Le script d'installation KServe peut aussi avoir besoin de kustomize et yq
  for t in kustomize yq; do
    command -v "$t" >/dev/null 2>&1 || echo "Attention : '$t' absent du PATH (peut être requis par le script KServe)." >&2
  done
}

start_minikube() {
  if minikube status -p "$MINIKUBE_PROFILE" >/dev/null 2>&1; then
    echo ">> Cluster minikube '$MINIKUBE_PROFILE' déjà démarré."
  else
    echo ">> Démarrage de minikube ($MINIKUBE_CPUS CPU, ${MINIKUBE_MEMORY} Mo, driver $MINIKUBE_DRIVER)..."
    local args=(start -p "$MINIKUBE_PROFILE"
      --cpus "$MINIKUBE_CPUS" --memory "$MINIKUBE_MEMORY"
      --disk-size "$MINIKUBE_DISK" --driver "$MINIKUBE_DRIVER")
    [[ -n "$K8S_VERSION" ]] && args+=(--kubernetes-version "$K8S_VERSION")
    minikube "${args[@]}"
  fi
  kubectl config use-context "$KCTX" >/dev/null
}

install() {
  check_tools
  start_minikube

  echo ">> Téléchargement du script d'installation KServe ${KSERVE_VERSION}..."
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "$INSTALL_SCRIPT_URL" -o "$tmp"
  echo "   Script sauvegardé dans $tmp (relisez-le si besoin)."

  echo ">> Installation de cert-manager, Istio, Knative et KServe (plusieurs minutes)..."
  bash "$tmp"

  echo ">> Attente des composants..."
  kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=600s
  kubectl wait --for=condition=Available deployment --all -n istio-system --timeout=600s
  kubectl wait --for=condition=Available deployment --all -n knative-serving --timeout=600s
  kubectl wait --for=condition=Available deployment --all -n kserve --timeout=600s

  echo
  echo "KServe ${KSERVE_VERSION} est installé (mode serverless)."
  echo "Prochaine étape : ./kserve-minikube.sh test"
}

test_isvc() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  echo ">> Déploiement de l'InferenceService de test LLAMA..."
  kubectl apply -f "$here/vLLM.yaml"
  kubectl wait --for=condition=Ready inferenceservice/llama-3-2-1b --timeout=600s
  kubectl apply -f "$here/streamlit.yaml"

  echo ">> Port-forward de l'interface streamlit sur localhost:8501..."
  kubectl port-forward svc/streamlit 8501:80 >/dev/null &&
  echo ">> Accédez à l'interface ici http://localhost:8501"
}

delete_isvc() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  echo ">> Suppression de l'interface de test et du déploiement de l'InferenceService de test LLAMA..."
  kubectl delete -f "$here/streamlit.yaml"
  kubectl delete -f "$here/vLLM.yaml"
  echo ">> Ressources supprimées !"
}

uninstall() {
  kubectl config use-context "$KCTX" >/dev/null
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "$INSTALL_SCRIPT_URL" -o "$tmp"
  bash "$tmp" --uninstall
}

delete_cluster() {
  minikube delete -p "$MINIKUBE_PROFILE"
}

case "${1:-}" in
  install)   install ;;
  test)      test_isvc ;;
  close)     delete_isvc ;;
  uninstall) uninstall ;;
  delete)    delete_cluster ;;
  *)
    sed -n '2,12p' "$0"
    exit 1
    ;;
esac