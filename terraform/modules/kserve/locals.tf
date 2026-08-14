locals {
  # Split multi-doc YAML into deterministic, index-addressable documents.
  knative_serving_crds_docs = [
    for d in split("\n---\n", data.http.knative_serving_crds.response_body) :
    trimspace(d) if trimspace(d) != ""
  ]

  knative_serving_core_docs = [
    for d in split("\n---\n", data.http.knative_serving_core.response_body) :
    trimspace(d) if trimspace(d) != ""
  ]

  knative_net_istio_docs = [
    for d in split("\n---\n", data.http.knative_net_istio.response_body) :
    trimspace(d) if trimspace(d) != ""
  ]

  kserve_all_docs = [
    for d in split("\n---\n", data.http.kserve_all.response_body) :
    trimspace(d) if trimspace(d) != ""
  ]

  knative_serving_crds_manifest_map = {
    for idx, doc in local.knative_serving_crds_docs :
    tostring(idx) => doc
  }

  knative_serving_core_namespace_manifest_map = {
    for idx, doc in local.knative_serving_core_docs :
    tostring(idx) => doc
    if can(regex("(?m)^kind:\\s*Namespace\\s*$", doc))
  }

  # Apply prerequisite Knative objects first so core pods can boot without crashing.
  knative_serving_core_prereq_manifest_map = {
    for idx, doc in local.knative_serving_core_docs :
    tostring(idx) => doc
    if can(regex("(?m)^kind:\\s*ConfigMap\\s*$", doc)) ||
    can(regex("(?m)^kind:\\s*ServiceAccount\\s*$", doc)) ||
    can(regex("(?m)^kind:\\s*Role\\s*$", doc)) ||
    can(regex("(?m)^kind:\\s*RoleBinding\\s*$", doc)) ||
    can(regex("(?m)^kind:\\s*ClusterRole\\s*$", doc)) ||
    can(regex("(?m)^kind:\\s*ClusterRoleBinding\\s*$", doc)) ||
    can(regex("(?m)^kind:\\s*Service\\s*$", doc))
  }

  # Apply regular Knative runtime resources after prerequisites are present.
  knative_serving_core_runtime_manifest_map = {
    for idx, doc in local.knative_serving_core_docs :
    tostring(idx) => doc
    if !can(regex("(?m)^kind:\\s*ConfigMap\\s*$", doc)) &&
    !can(regex("(?m)^kind:\\s*Namespace\\s*$", doc)) &&
    !can(regex("(?m)^kind:\\s*ServiceAccount\\s*$", doc)) &&
    !can(regex("(?m)^kind:\\s*Role\\s*$", doc)) &&
    !can(regex("(?m)^kind:\\s*RoleBinding\\s*$", doc)) &&
    !can(regex("(?m)^kind:\\s*ClusterRole\\s*$", doc)) &&
    !can(regex("(?m)^kind:\\s*ClusterRoleBinding\\s*$", doc)) &&
    !can(regex("(?m)^kind:\\s*Service\\s*$", doc)) &&
    !can(regex("(?m)^apiVersion:\\s*networking\\.internal\\.knative\\.dev/", doc))
  }

  knative_serving_core_webhook_manifest_map = {
    for idx, doc in local.knative_serving_core_docs :
    tostring(idx) => doc
    if can(regex("(?m)^apiVersion:\\s*networking\\.internal\\.knative\\.dev/", doc))
  }

  knative_net_istio_manifest_map = {
    for idx, doc in local.knative_net_istio_docs :
    tostring(idx) => doc
  }

  kserve_crd_manifest_map = {
    for idx, doc in local.kserve_all_docs :
    tostring(idx) => doc if can(regex("(?m)^kind:\\s*CustomResourceDefinition\\s*$", doc))
  }

  kserve_namespace_manifest_map = {
    for idx, doc in local.kserve_all_docs :
    tostring(idx) => doc if can(regex("(?m)^kind:\\s*Namespace\\s*$", doc))
  }

  kserve_non_crd_manifest_map = {
    for idx, doc in local.kserve_all_docs :
    tostring(idx) => doc
    if !can(regex("(?m)^kind:\\s*CustomResourceDefinition\\s*$", doc)) &&
    !can(regex("(?m)^kind:\\s*Namespace\\s*$", doc))
  }
}