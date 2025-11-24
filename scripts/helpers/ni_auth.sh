#!/usr/bin/env bash
# Automate NiFi User Authorization

# Find-or-create NiFi user by DN; echo userId
ni::auth::ensure_user() {
  local identity="$1"
  # search by identity (tenants search can return users and groups)
  local controller="${NIFI_NODES[0]}"               # query any node
  local api="$(ni::api::api_base_for "$controller")"
  local r; r=$(ni::api::curl_nifi "${api}/tenants/search-results?q=$(ni::api::urlenc "$identity")") || true
  local id; id=$(jq -r --arg id "$identity" '
    (.users[]?.component | select(.identity==$id).id) // empty
  ' <<<"$r")
  if [[ -z "$id" ]]; then
    # create
    r=$(ni::api::curl_nifi -X POST "${api}/tenants/users" -d @- <<JSON
{"revision":{"version":0},"component":{"identity":"$identity"}}
JSON
) || true
    # If the POST collides (409), re-query
    id=$(jq -r '.component.id? // empty' <<<"$r")
    if [[ -z "$id" ]]; then
      r=$(ni::api::curl_nifi "${api}/tenants/search-results?q=$(ni::api::urlenc "$identity")")
      id=$(jq -r --arg id "$identity" '
        (.users[]?.component | select(.identity==$id).id) // empty
      ' <<<"$r")
    fi
  fi
  [[ -n "$id" ]] || { echo "ERR: could not ensure user $identity" >&2; return 1; }
  echo "$id"
}

reg::auth::ensure_user() {
  local identity="${1:?DN required}"
  local host="${REGISTRY_HOST:?set REGISTRY_HOST (e.g. nifi-registry)}"
  local api; api="$(reg::api::api_base_for "$host")"

  local r uid
  r="$(ni::api::curl_nifi "${api}/tenants/users")"

  # Normalize: if the payload is an array, use it; if it's an object, use its .users array.
  uid="$(
    jq -r --arg id "$identity" '
      ( if type=="array" then . else .users end ) as $arr
      | first($arr[]? | select(.identity==$id) | .identifier) // empty
    ' <<<"$r"
  )"

  if [[ -z "$uid" ]]; then
    r="$(ni::api::curl_nifi -X POST "${api}/tenants/users" \
         -d "$(jq -n --arg identity "$identity" '{identity:$identity}')" )"
    # POST returns the created user object in both shapes
    uid="$(jq -r '.identifier // ( .user.identifier // empty )' <<<"$r")"
  fi

  [[ -n "$uid" ]] || { echo "ERR: could not ensure registry user $identity" >&2; return 1; }
  echo "$uid"
}

# returns policy JSON or empty on failure
ni::auth::get_policy_by_resource() {
  local action="$1" resource="$2"
  local controller="${NIFI_NODES[0]}"
  local api; api="$(ni::api::api_base_for "$controller")"

  # 3 shapes to try
  local enc1; enc1="$(printf '%s' "$resource" | jq -sRr @uri)"         # e.g. %2Fflow
  local enc2; enc2="$(printf '%%25s' "${enc1#%}")"                      # e.g. %252Fflow
  # ^ turns %2Fflow -> %252Fflow  (double-encoded)

  local urls=(
    "${api}/policies/${action}/${enc1}"
    "${api}/policies/${action}/${enc2}"
    "${api}/policies/${action}/${resource}"
  )

  local u r
  for u in "${urls[@]}"; do
    r=$(ni::api::curl_nifi "$u" 2>/dev/null) && { echo "$r"; return 0; }
  done
  echo ""
  return 1
}

# GET policy by action/resource (tries raw, %enc, %25-double-enc)
reg::auth::get_policy_by_resource() {
  local action="${1:?READ|WRITE}"; local resource="${2:?/path}"
  local host="${REGISTRY_HOST:?set REGISTRY_HOST}"
  local api; api="$(reg::api::api_base_for "$host")"
  local enc1; enc1="$(printf '%s' "$resource" | jq -sRr @uri)"
  local enc2; enc2="$(printf '%%25s' "${enc1#%}")"
  local urls=(
    "${api}/policies/${action}/${resource}"
    "${api}/policies/${action}/${enc1}"
    "${api}/policies/${action}/${enc2}"
  )
  local u r
  for u in "${urls[@]}"; do
    r="$(ni::api::curl_nifi "$u" 2>/dev/null)" && { echo "$r"; return 0; }
  done
  echo ""; return 1
}

# Get (or create) a policy; args: action read|write, resource "/flow" etc.
# echoes policy id
ni::auth::ensure_policy() {
  local action="$1" resource="$2"
  local controller="${NIFI_NODES[0]}"
  local api; api="$(ni::api::api_base_for "$controller")"

  # 1) try to GET the policy by resource using fallback shapes
  local r pid
  r=$(ni::auth::get_policy_by_resource "$action" "$resource") || true
  pid=$(jq -r '.component.id? // empty' <<<"$r")
  if [[ -n "$pid" ]]; then echo "$pid"; return 0; fi

  # 2) create (409 is fine)
  r="$(ni::api::curl_nifi -X POST "${api}/policies" -d "$(jq -n --arg action "$action" --arg resource "/$resource" '{"revision": { "version": 0 }, "component": {"action": $action, "resource": $resource, "users":[], "userGroups":[]}}')")" || true

  # 3) re-GET via fallback
  attempts=5
  delay=1
  for ((i=1; i<=attempts; i++)); do
    r=$(ni::auth::get_policy_by_resource "$action" "$resource") || true
    pid=$(jq -r '.component.id? // empty' <<<"$r")
    if [ -n "$pid" ]; then
      echo "$pid"
      return 0
    fi
    if [ "$i" -lt "$attempts" ]; then
      sleep "$delay"
      delay=$(( delay < 8 ? delay * 2 : 8 ))
    fi
  done
  echo "ERR: could not ensure policy $action $resource" >&2
  return 1
}

# Ensure a top-level policy exists; echo policy identifier
reg::auth::ensure_policy() {
  local action="$1" resource="$2"
  local host="${REGISTRY_HOST:?set REGISTRY_HOST}"
  local api; api="$(reg::api::api_base_for "$host")"

  local r pid
  r="$(reg::auth::get_policy_by_resource "$action" "$resource")" || true
  pid="$(jq -r '.identifier? // empty' <<<"$r")"
  if [[ -n "$pid" ]]; then echo "$pid"; return 0; fi

  r="$(ni::api::curl_nifi -X POST "${api}/policies" -d "$(jq -n --arg action "$action" --arg resource "/$resource" '{action:$action,resource:$resource,users:[],userGroups:[]}')")" || true
  pid="$(jq -r '.identifier? // empty' <<<"$r")"
  if [[ -z "$pid" ]]; then
    r="$(reg::auth::get_policy_by_resource "$action" "$resource")" || true
    pid="$(jq -r '.identifier? // empty' <<<"$r")"
  fi
  [[ -n "$pid" ]] || { echo "ERR: could not ensure registry policy $action $resource" >&2; return 1; }
  echo "$pid"
}

# add a user to a policy (true idempotent, uses current revision from GET)
ni::auth::add_user_to_policy() {
  local policy_id="$1" user_id="$2"
  # fetch current, merge user if missing, PUT back
  local controller="${NIFI_NODES[0]}"               # query any node
  local api="$(ni::api::api_base_for "$controller")"
  local r; r=$(ni::api::curl_nifi "${api}/policies/${policy_id}") || return 1
  local has; has=$(jq -r --arg uid "$user_id" '[.component.users[]?.id==$uid]|any' <<<"$r")
  [[ "$has" == "true" ]] && return 0
  # Use EXACT revision from GET; do not increment yourself
  local body; body=$(jq --arg uid "$user_id" '
    .component.users += [{"id":$uid}]
  ' <<<"$r")
  ni::api::curl_nifi -X PUT "${api}/policies/${policy_id}" -d "$body" >/dev/null \
    || {
      # If PUT 409s, re-GET and retry once
      r=$(ni::api::curl_nifi "${api}/policies/${policy_id}")
      body=$(jq --arg uid "$user_id" '
        .component.users += [{"id":$uid}]
      ' <<<"$r")
      ni::api::curl_nifi -X PUT "${api}/policies/${policy_id}" -d "$body" >/dev/null
    }
}

# Add user to policy (idempotent; revision is internal to Registry, PUT is whole policy doc)
reg::auth::add_user_to_policy() {
  local policy_id="${1:?}"; local user_id="${2:?}"
  local host="${REGISTRY_HOST:?set REGISTRY_HOST}"
  local api; api="$(reg::api::api_base_for "$host")"
  local r has upd
  r="$(ni::api::curl_nifi "${api}/policies/${policy_id}")"
  has="$(jq -e --arg uid "$user_id" '.users[]?.identifier == $uid' <<<"$r" >/dev/null 2>&1 && echo yes || echo no)"
  [[ "$has" == "yes" ]] && return 0
  upd="$(jq --arg uid "$user_id" '.users += [{"identifier":$uid}]' <<<"$r")"
  ni::api::curl_nifi -X PUT "${api}/policies/${policy_id}" -d "$upd" >/dev/null
}

# Convenience: ensure user is on (action, resource)
ni::auth::grant() {
  local identity="$1" action="$2" resource="$3"
  local uid; uid=$(ni::auth::ensure_user "$identity") || return 1
  local pid; pid=$(ni::auth::ensure_policy "$action" "$resource") || return 1
  ni::auth::add_user_to_policy "$pid" "$uid"
  printf 'granted %-5s on %-40s to %s\n' "$action" "$resource" "$identity"
}

# Ensure (find-or-create) a bucket by name; echo bucket identifier
reg::auth::ensure_bucket() {
  local name="${1:?bucket name required}"
  local host="${REGISTRY_HOST:?set REGISTRY_HOST}"
  local api; api="$(reg::api::api_base_for "$host")"
  local r bid
  r="$(ni::api::curl_nifi "${api}/buckets")"
  bid="$(jq -r --arg name "$name" 'first(.[] | select(.name==$name) | .identifier) // empty' <<<"$r")"
  if [[ -z "$bid" ]]; then
    r="$(ni::api::curl_nifi -X POST "${api}/buckets" -d "$(jq -n --arg name "$name" '{name:$name,description:"Automated bucket"}')")"
    bid="$(jq -r '.identifier' <<<"$r")"
  fi
  [[ -n "$bid" ]] || { echo "ERR: could not ensure bucket $name" >&2; return 1; }
  echo "$bid"
}

ni::auth::grant_nodes() {
  local admin="CN=${NIFI_USER}, OU=NIFI"
  local NODES=()
  for h in "${NIFI_NODES[@]}"; do
    NODES+=( "CN=${h}, OU=NIFI" )
  done
  
  # Global (controller-level) policies
  ni::auth::grant "$admin" read  "flow"                   # view the user interface
  for dn in "${NODES[@]}"; do ni::auth::grant "$dn" read "flow"; done

  ni::auth::grant "$admin" read  "provenance"            # query provenance
  ni::auth::grant "$admin" read  "site-to-site"          # retrieve site-to-site details
  for dn in "${NODES[@]}"; do ni::auth::grant "$dn" read "site-to-site"; done

  ni::auth::grant "$admin" read  "system"                # view system diagnostics
  ni::auth::grant "$admin" write "proxy"                 # proxy user requests

  ni::auth::grant "$admin" read  "counters"              # access counters (view)
  ni::auth::grant "$admin" write "counters"              # access counters (modify)
  
  # Restricted Components: allow referencing external resources (e.g., driver JARs)
  for dn in "${NODES[@]}"; do
    ni::auth::grant "$dn" write "restricted-components"
  done

  # Root process group (top-level canvas) policies
  local controller="${NIFI_NODES[0]}"               # query any node
  local api="$(ni::api::api_base_for "$controller")"
  ROOT_JSON=$(ni::api::curl_nifi "${api}/flow/process-groups/root")
  ROOT_ID=$(jq -r '.processGroupFlow.id // .processGroupFlow.processGroup.id // .id' <<<"$ROOT_JSON")
  test -n "$ROOT_ID" || { echo "Root id not found"; exit 1; }

  RES_COMPONENT="process-groups/${ROOT_ID}"
  RES_DATA="data/process-groups/${ROOT_ID}"
  RES_OPERATION="operation/process-groups/${ROOT_ID}"
  RES_PROVENANCE="provenance-data/process-groups/${ROOT_ID}"

  # Component permissions: view/modify the component on the root canvas
  ni::auth::grant "$admin" read  "${RES_COMPONENT}"
  ni::auth::grant "$admin" write "${RES_COMPONENT}"

  # Data permissions: view/modify the data on the root canvas
  ni::auth::grant "$admin" read  "${RES_DATA}"
  ni::auth::grant "$admin" write "${RES_DATA}"

  # Operation permissions: write the operation on the root canvas
  ni::auth::grant "$admin" write "${RES_OPERATION}"

  # Provenance permissions: read the provenance on the root canvas
  ni::auth::grant "$admin" read "${RES_PROVENANCE}"

  # Also add node DNs for canvas component & data perms (matches your checklist)
  for dn in "${NODES[@]}"; do
    ni::auth::grant "$dn" read  "${RES_COMPONENT}"
    ni::auth::grant "$dn" write "${RES_COMPONENT}"
    ni::auth::grant "$dn" read  "${RES_DATA}"
    ni::auth::grant "$dn" write "${RES_DATA}"
    ni::auth::grant "$dn" write "${RES_OPERATION}"
  done
}

# Bootstrap: users (node DNs), bucket, and top-level policies (/buckets READ+WRITE, /proxy WRITE)
# Usage:
#   export REGISTRY_HOST=nifi-registry
#   NIFI_NODES=(nifi-node-01 nifi-node-02)
#   ni::reg::bootstrap "Main Flows"
reg::auth::bootstrap() {
  local bucket_name="${1:?bucket name}"; shift
  local NODES=()
  for h in "${NIFI_NODES[@]}"; do
    NODES+=( "CN=${h}, OU=NIFI" )
  done

  local bucket_id; bucket_id="$(reg::auth::ensure_bucket "$bucket_name")"
  echo "Bucket OK: $bucket_name ($bucket_id)"

  # Ensure policies
  local pol_buckets_read pol_buckets_write pol_proxy_read pol_proxy_write
  pol_buckets_read="$(reg::auth::ensure_policy READ  buckets)"
  pol_buckets_write="$(reg::auth::ensure_policy WRITE buckets)"
  pol_proxy_read="$(reg::auth::ensure_policy READ proxy)"
  pol_proxy_write="$(reg::auth::ensure_policy WRITE proxy)"

  echo "Policies OK: /buckets (READ $pol_buckets_read, WRITE $pol_buckets_write), /proxy (READ $pol_proxy_read, WRITE $pol_proxy_write)"

  # Ensure users + grants
  local dn uid
  for dn in "${NODES[@]}"; do
    uid="$(reg::auth::ensure_user "$dn")"
    reg::auth::add_user_to_policy "$pol_buckets_read"  "$uid"
    reg::auth::add_user_to_policy "$pol_buckets_write" "$uid"
    reg::auth::add_user_to_policy "$pol_proxy_read"    "$uid"
    reg::auth::add_user_to_policy "$pol_proxy_write"   "$uid"
    printf 'Registry grants done for %s (READ/WRITE /buckets, READ/WRITE /proxy)\n' "$dn"
  done

  echo "Registry bootstrap complete."
}
