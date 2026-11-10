#!/usr/bin/env bash
# Déploie KServe (mode serverless / Knative) sur un minikube local.
#
# Usage :
#   ./kserve-minikube.sh install     # démarre minikube + installe KServe et ses dépendances
#   ./kserve-minikube.sh test        # déploie un modèle sklearn de test et l'appelle
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

  echo ">> Déploiement de l'InferenceService de test..."
  kubectl apply -f "$here/sklearn-iris.yaml"
  kubectl wait --for=condition=Ready inferenceservice/sklearn-iris --timeout=600s

  echo ">> Port-forward de l'ingress gateway Istio sur localhost:8080..."
  kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/dev/null 2>&1 &
  local pf=$!
  trap 'kill $pf 2>/dev/null || true' EXIT
  sleep 3

  local host
  host="$(kubectl get inferenceservice sklearn-iris -o jsonpath='{.status.url}' | sed 's#^https\?://##')"
  echo ">> Appel du modèle (Host: $host)..."
  curl -sS -H "Host: ${host}" -H "Content-Type: application/json" \
    http://localhost:8080/v1/models/sklearn-iris:predict \
    -d '{"instances": [[6.8, 2.8, 4.8, 1.4], [6.0, 3.4, 4.5, 1.6]]}'
  echo
  echo
  echo "Résultat attendu : {\"predictions\":[1,1]}"
  echo "Observez le scale-to-zero : kubectl get pods -w (le pod disparaît après ~60 s d'inactivité)."
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
  uninstall) uninstall ;;
  delete)    delete_cluster ;;
  *)
    sed -n '2,12p' "$0"
    exit 1
    ;;
esac