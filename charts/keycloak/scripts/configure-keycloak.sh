#!/usr/bin/env bash
#
# Post-deploy configuration for a freshly installed Keycloak: realm, session/
# audit settings, service client, UI client, realm roles and groups.
# Idempotent — every step creates on first run and updates on later ones, so
# it is safe to run on every deploy.
#
# Required environment:
#   KC_BASE_URL             Keycloak base URL, e.g. https://127.0.0.1:8443
#   KC_ADMIN_USER           master-realm admin username
#   KC_ADMIN_PASSWORD       master-realm admin password (never hardcode)
#   KC_SERVICE_CLIENT_SECRET
#                           dpn-service-client's client secret (never
#                           hardcode) — sourced from the KC-SERVICE-CLIENT-
#                           SECRET Key Vault entry and asserted on every run,
#                           so it never drifts from what the oauth2-proxy
#                           sidecars in dpn-health-monitoring-service already
#                           have configured. Without this, Keycloak
#                           auto-generates a fresh random secret the first
#                           time the client is created, and every consumer
#                           that already has the old value starts failing
#                           token exchange with "unauthorized_client".
#
# Optional environment (defaults in brackets):
#   KC_REALM                 [dpn-realm]
#   KC_REALM_DISPLAY_NAME    [DPN-Authentication-Platform]
#   KC_SSO_IDLE_TIMEOUT_SECONDS
#                            How long an untouched SSO session survives [1800]
#   KC_SSO_MAX_LIFESPAN_SECONDS
#                            Hard ceiling regardless of activity [28800]
#   KC_REMEMBER_ME           "Remember Me" persistent login cookie [false]
#   KC_LOGIN_THEME           Login theme applied realm-wide (every UI's login
#                            screen) [dpn-portal]. Theme files live under
#                            charts/keycloak/themes/dpn-portal and are packaged
#                            by templates/theme-configmap.yaml.
#   KC_DISPLAY_NAME_HTML     Realm header markup shown above the login form
#                            [<span class="dpn-kc-brand"><strong>DSI DPN Platform</strong></span>]
#   KC_CLIENT_ID             machine-to-machine client [DPN-Client]
#   KC_CLIENT_NAME           [DPN-Client]
#   KC_CLIENT_DESCRIPTION    [DPN Application]
#   KC_REALM_ROLES           comma-separated name:description pairs, mapped
#                            onto the machine client's service account
#                            [dpnreader:Read-only access to all DPN UI components,dpnadmin:Full read/write access to all DPN UI components,dpnoperator:Can trigger and enable/disable DPN DAGs and manage task state; cannot edit or delete DAGs]
#   KC_EVENTS_EXPIRATION     audit retention in seconds [31536000 = 365 days]
#   KC_UI_CLIENT_ID          browser-facing shared UI client [dpn-service-client]
#   KC_UI_CLIENT_NAME        [DPN Service Client (shared by all UIs)]
#   KC_UI_CLIENT_DESCRIPTION [DPN Application]
#   KC_UI_HOST_KAFKA_UI      [dpn-observability.ns-dpn-health-01.svc.cluster.local:8082]
#   KC_UI_HOST_KAFKA_UI_2    [dpn-kafka-ui-external.ns-dpn-01.svc.cluster.local:8086]
#                            dpn-platform/dpn-federator-gateway's own Kafka
#                            UI instance (dpn-kafka-ui.ns-dpn-01) — reached
#                            directly via its own "-external" LoadBalancer
#                            Service, same native Keycloak OIDC login as
#                            KC_UI_HOST_KAFKA_UI above
#                            (kafkaUI.oidcRbac.browserHost in
#                            dpn-federator-gateway's charts/dpn-platform
#                            values files, same across every environment).
#                            The oauth2-proxy gateway this used to sit
#                            behind was removed from dpn-health-monitoring-
#                            service with no replacement (see that repo's
#                            charts/oauth2-proxy/README.md) — this UI is not
#                            owned by that repo.
#   KC_UI_HOST_AIRFLOW       [dpn-airflow-webserver-external.ns-dpn-01.svc.cluster.local]
#                            No port — Airflow's own Flask-AppBuilder OAuth
#                            flow (dpn-data-pipelines' webserver_config.py)
#                            builds its redirect_uri dynamically from
#                            whatever host the browser used, forced to
#                            https:// regardless of the pod's own plain-HTTP
#                            connection. It no longer sits behind the shared
#                            dpn-observability oauth2-proxy gateway — that
#                            was removed with no replacement (see
#                            dpn-health-monitoring-service's
#                            charts/oauth2-proxy/README.md) — it's reached
#                            directly via its own LoadBalancer Service in
#                            ns-dpn-01 (dpn-data-pipelines' airflow-lb.yaml).
#   KC_UI_HOST_JAEGER        [dpn-observability.ns-dpn-health-01.svc.cluster.local:16686]
#   KC_UI_HOST_PERSES        [dpn-observability.ns-dpn-health-01.svc.cluster.local:8083]
#   KC_UI_HOST_OPENSEARCH_DASHBOARDS
#                            [dpn-observability.ns-dpn-health-01.svc.cluster.local:5601]
#   KC_UI_HOST_PORTAL        [dpn-observability.ns-dpn-health-01.svc.cluster.local:8443]
#                            All seven sit behind their own oauth2-proxy
#                            sidecar on the shared dpn-observability service
#                            (one port per UI) and callback at
#                            "/oauth2/callback". Keep the portal entry equal
#                            to externalUrl in dpn-health-monitoring-
#                            service's charts/dpn-portal/values.yaml and
#                            charts/oauth2-proxy/values-portal.yaml.
#   KC_UI_HOST_FEDERATOR_CLIENT_1
#                            [dpn-federator-client-1-external.ns-dpn-01.svc.cluster.local:8085]
#   KC_UI_HOST_FEDERATOR_CLIENT_2
#                            [dpn-federator-client-2-external.ns-dpn-01.svc.cluster.local:8085]
#                            dpn-federator-gateway's Job Runner dashboards —
#                            each runs its own JobRunnerAuthGateway OIDC
#                            browser login directly against dpn-service-client
#                            (no oauth2-proxy sidecar). The "-external"
#                            LoadBalancer Service, not the plain ClusterIP
#                            one — that's the actual public entry point the
#                            browser reaches (see federator-client-config.yaml's
#                            jobs.dashboard.auth.oidc.public.base.url), and
#                            the redirect URI must match it exactly.
#   KC_GROUPS                comma-separated group:role pairs — each Keycloak
#                            Group is created carrying its paired realm role,
#                            so adding a user to the group grants that role
#                            [dpn-admins:dpnadmin,dpn-readers:dpnreader,dpn-operators:dpnoperator]
#
# The machine client (KC_CLIENT_ID) is client-credentials only: no browser
# leg, no redirect URIs, no web origins. The UI client (KC_UI_CLIENT_ID) is
# the one shared confidential client every DPN UI authenticates against via
# its own oauth2-proxy sidecar.
#
set -euo pipefail

: "${KC_BASE_URL:?KC_BASE_URL is required}"
: "${KC_ADMIN_USER:?KC_ADMIN_USER is required}"
: "${KC_ADMIN_PASSWORD:?KC_ADMIN_PASSWORD is required}"
: "${KC_SERVICE_CLIENT_SECRET:?KC_SERVICE_CLIENT_SECRET is required}"

KC_REALM="${KC_REALM:-dpn-realm}"
KC_REALM_DISPLAY_NAME="${KC_REALM_DISPLAY_NAME:-DPN-Authentication-Platform}"
KC_SSO_IDLE_TIMEOUT_SECONDS="${KC_SSO_IDLE_TIMEOUT_SECONDS:-1800}"
KC_SSO_MAX_LIFESPAN_SECONDS="${KC_SSO_MAX_LIFESPAN_SECONDS:-28800}"
KC_REMEMBER_ME="${KC_REMEMBER_ME:-false}"
KC_LOGIN_THEME="${KC_LOGIN_THEME:-dpn-portal}"
KC_DISPLAY_NAME_HTML="${KC_DISPLAY_NAME_HTML:-<span class=\"dpn-kc-brand\"><strong>DSI DPN Platform</strong></span>}"
KC_CLIENT_ID="${KC_CLIENT_ID:-DPN-Client}"
KC_CLIENT_NAME="${KC_CLIENT_NAME:-DPN-Client}"
KC_CLIENT_DESCRIPTION="${KC_CLIENT_DESCRIPTION:-DPN Application}"
KC_REALM_ROLES="${KC_REALM_ROLES:-dpnreader:Read-only access to all DPN UI components,dpnadmin:Full read/write access to all DPN UI components,dpnoperator:Can trigger and enable/disable DPN DAGs and manage task state; cannot edit or delete DAGs}"
KC_EVENTS_EXPIRATION="${KC_EVENTS_EXPIRATION:-31536000}"
KC_UI_CLIENT_ID="${KC_UI_CLIENT_ID:-dpn-service-client}"
KC_UI_CLIENT_NAME="${KC_UI_CLIENT_NAME:-DPN Service Client (shared by all UIs)}"
KC_UI_CLIENT_DESCRIPTION="${KC_UI_CLIENT_DESCRIPTION:-DPN Application}"
KC_UI_HOST_KAFKA_UI="${KC_UI_HOST_KAFKA_UI:-dpn-observability.ns-dpn-health-01.svc.cluster.local:8082}"
KC_UI_HOST_KAFKA_UI_2="${KC_UI_HOST_KAFKA_UI_2:-dpn-kafka-ui-external.ns-dpn-01.svc.cluster.local:8086}"
KC_UI_HOST_AIRFLOW="${KC_UI_HOST_AIRFLOW:-dpn-airflow-webserver-external.ns-dpn-01.svc.cluster.local:8080}"
KC_UI_HOST_JAEGER="${KC_UI_HOST_JAEGER:-dpn-observability.ns-dpn-health-01.svc.cluster.local:16686}"
KC_UI_HOST_PERSES="${KC_UI_HOST_PERSES:-dpn-observability.ns-dpn-health-01.svc.cluster.local:8083}"
KC_UI_HOST_OPENSEARCH_DASHBOARDS="${KC_UI_HOST_OPENSEARCH_DASHBOARDS:-dpn-observability.ns-dpn-health-01.svc.cluster.local:5601}"
KC_UI_HOST_PORTAL="${KC_UI_HOST_PORTAL:-dpn-observability.ns-dpn-health-01.svc.cluster.local:8443}"
KC_UI_HOST_FEDERATOR_CLIENT_1="${KC_UI_HOST_FEDERATOR_CLIENT_1:-dpn-federator-client-1-external.ns-dpn-01.svc.cluster.local:8085}"
KC_UI_HOST_FEDERATOR_CLIENT_2="${KC_UI_HOST_FEDERATOR_CLIENT_2:-dpn-federator-client-2-external.ns-dpn-01.svc.cluster.local:8085}"
KC_GROUPS="${KC_GROUPS:-dpn-admins:dpnadmin,dpn-readers:dpnreader,dpn-operators:dpnoperator}"

# The server presents the dpn-tls certificate, whose SANs do not cover the
# address this script reaches it on. -k is safe here: the connection is either
# a local port-forward or stays inside the cluster VNet.
CURL=(curl -sS -k --max-time 60)

TOKEN=""

# api <METHOD> <PATH> [BODY] — returns "<http_code>\n<body>"
api() {
  local method="$1" path="$2" body="${3:-}"
  local args=("${CURL[@]}" -X "$method" -w '\n%{http_code}'
              -H "Authorization: Bearer ${TOKEN}")
  if [ -n "$body" ]; then
    args+=(-H 'Content-Type: application/json' -d "$body")
  fi
  "${args[@]}" "${KC_BASE_URL}${path}"
}

http_code() { printf '%s' "$1" | tail -n1; }
http_body() { printf '%s' "$1" | sed '$d'; }

# Treats 409 Conflict as "already there" so callers can fall through to a PUT.
created_or_exists() {
  local code="$1"
  [ "$code" = "201" ] || [ "$code" = "409" ]
}

# upsert_protocol_mapper <client_uuid> <mapper_name> <payload> — create the
# mapper if it doesn't exist, else PUT it. Keycloak's PUT for an existing
# mapper requires "id" in the body to match the path, or it throws a 500
# rather than a clean 400, so that gets merged in on the update path only.
upsert_protocol_mapper() {
  local client_uuid="$1" mapper_name="$2" payload="$3"
  local resp code mapper_id

  resp=$(api GET "/admin/realms/${KC_REALM}/clients/${client_uuid}/protocol-mappers/models")
  mapper_id=$(http_body "$resp" | jq -r --arg name "$mapper_name" '.[] | select(.name == $name) | .id // empty')

  if [ -n "$mapper_id" ]; then
    payload=$(printf '%s' "$payload" | jq -c --arg id "$mapper_id" '. + {id: $id}')
    resp=$(api PUT "/admin/realms/${KC_REALM}/clients/${client_uuid}/protocol-mappers/models/${mapper_id}" "$payload")
    code=$(http_code "$resp")
    case "$code" in
      200|204) echo "  already existed, updated" ;;
      *) echo "##[error]Mapper ${mapper_name} update failed (HTTP $code)"; http_body "$resp"; exit 1 ;;
    esac
  else
    resp=$(api POST "/admin/realms/${KC_REALM}/clients/${client_uuid}/protocol-mappers/models" "$payload")
    code=$(http_code "$resp")
    if ! created_or_exists "$code"; then
      echo "##[error]Mapper ${mapper_name} create failed (HTTP $code)"
      http_body "$resp"
      exit 1
    fi
    echo "  created"
  fi
}

# upsert_realm_role <name> <description> — create/update a realm role and
# echo its internal id. Shared by every step below that maps a role onto a
# service account or a group, so the description stays consistent wherever
# the role is (re-)created.
upsert_realm_role() {
  local name="$1" desc="$2" resp code

  echo "Realm role: ${name}"
  local payload
  payload=$(jq -nc --arg name "$name" --arg desc "$desc" '{name: $name, description: $desc}')

  resp=$(api POST "/admin/realms/${KC_REALM}/roles" "$payload")
  code=$(http_code "$resp")
  if [ "$code" = "409" ]; then
    resp=$(api PUT "/admin/realms/${KC_REALM}/roles/${name}" "$payload")
    code=$(http_code "$resp")
    case "$code" in
      200|204) echo "  already existed, updated" ;;
      *) echo "##[error]Role update failed (HTTP $code)"; http_body "$resp"; exit 1 ;;
    esac
  elif [ "$code" = "201" ]; then
    echo "  created"
  else
    echo "##[error]Role create failed (HTTP $code)"
    http_body "$resp"
    exit 1
  fi
}

# realm_role_id <name> — resolve a realm role's internal id, or fail.
realm_role_id() {
  local name="$1" resp id
  resp=$(api GET "/admin/realms/${KC_REALM}/roles/${name}")
  id=$(http_body "$resp" | jq -r '.id // empty')
  if [ -z "$id" ]; then
    echo "##[error]Could not resolve id for realm role ${name}." >&2
    exit 1
  fi
  printf '%s' "$id"
}

# map_role_to_user <user_id> <role_name> <role_id> <what> — assign a realm
# role to a user (typically a client's service-account user).
map_role_to_user() {
  local user_id="$1" role_name="$2" role_id="$3" what="$4" resp code
  local payload
  payload=$(jq -nc --arg id "$role_id" --arg name "$role_name" '[{id: $id, name: $name}]')
  resp=$(api POST "/admin/realms/${KC_REALM}/users/${user_id}/role-mappings/realm" "$payload")
  code=$(http_code "$resp")
  case "$code" in
    200|204) echo "  mapped to the ${what} service account" ;;
    *) echo "##[error]Role mapping failed (HTTP $code)"; http_body "$resp"; exit 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Step 1 — authenticate against the master realm
# ---------------------------------------------------------------------------
echo "Authenticating to ${KC_BASE_URL} as ${KC_ADMIN_USER}"

TOKEN_RESPONSE=$("${CURL[@]}" -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'client_id=admin-cli' \
  --data-urlencode 'grant_type=password' \
  --data-urlencode "username=${KC_ADMIN_USER}" \
  --data-urlencode "password=${KC_ADMIN_PASSWORD}" \
  "${KC_BASE_URL}/realms/master/protocol/openid-connect/token") || {
    echo "##[error]Could not reach the token endpoint at ${KC_BASE_URL}."
    exit 1
  }

TOKEN=$(printf '%s' "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
if [ -z "$TOKEN" ]; then
  echo "##[error]Authentication failed. Check KEYCLOAK-ADMIN-PASSWORD in Key Vault."
  printf '%s\n' "$TOKEN_RESPONSE" | jq -r '.error_description // .error // .' 2>/dev/null || true
  exit 1
fi
echo "Authenticated."

# ---------------------------------------------------------------------------
# Step 2 — realm, including session bounds and event settings
# ---------------------------------------------------------------------------
echo "Realm: ${KC_REALM}"

REALM_PAYLOAD=$(jq -nc \
  --arg realm "$KC_REALM" \
  --arg display "$KC_REALM_DISPLAY_NAME" \
  --arg loginTheme "$KC_LOGIN_THEME" \
  --arg displayNameHtml "$KC_DISPLAY_NAME_HTML" \
  --argjson idleTimeout "$KC_SSO_IDLE_TIMEOUT_SECONDS" \
  --argjson maxLifespan "$KC_SSO_MAX_LIFESPAN_SECONDS" \
  --argjson rememberMe "$KC_REMEMBER_ME" \
  '{
     realm: $realm,
     enabled: true,
     displayName: $display,
     displayNameHtml: $displayNameHtml,
     loginTheme: $loginTheme,
     sslRequired: "external",
     registrationAllowed: false,
     eventsEnabled: true,
     adminEventsEnabled: true,
     adminEventsDetailsEnabled: true,
     ssoSessionIdleTimeout: $idleTimeout,
     ssoSessionMaxLifespan: $maxLifespan,
     rememberMe: $rememberMe
   }')

RESP=$(api POST "/admin/realms" "$REALM_PAYLOAD")
CODE=$(http_code "$RESP")

if [ "$CODE" = "201" ]; then
  echo "  created"
elif [ "$CODE" = "409" ]; then
  RESP=$(api PUT "/admin/realms/${KC_REALM}" "$REALM_PAYLOAD")
  CODE=$(http_code "$RESP")
  case "$CODE" in
    200|204) echo "  already existed, updated" ;;
    *) echo "##[error]Realm update failed (HTTP $CODE)"; http_body "$RESP"; exit 1 ;;
  esac
else
  echo "##[error]Realm create failed (HTTP $CODE)"
  http_body "$RESP"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 3 — machine-to-machine service client
# ---------------------------------------------------------------------------
echo "Client: ${KC_CLIENT_ID} (client credentials)"

# Confidential client, service account only. standardFlowEnabled is off, so
# Keycloak never issues a browser redirect and redirect URIs are meaningless;
# the empty arrays keep an existing client from retaining stale ones.
CLIENT_PAYLOAD=$(jq -nc \
  --arg clientId "$KC_CLIENT_ID" \
  --arg name "$KC_CLIENT_NAME" \
  --arg description "$KC_CLIENT_DESCRIPTION" \
  '{
     clientId: $clientId,
     name: $name,
     description: $description,
     enabled: true,
     protocol: "openid-connect",
     redirectUris: [],
     webOrigins: [],
     frontchannelLogout: false,
     attributes: {
       "backchannel.logout.revoke.offline.tokens": "false",
       "backchannel.logout.session.required": "false"
     },
     publicClient: false,
     standardFlowEnabled: false,
     implicitFlowEnabled: false,
     directAccessGrantsEnabled: false,
     serviceAccountsEnabled: true
   }')

RESP=$(api GET "/admin/realms/${KC_REALM}/clients?clientId=${KC_CLIENT_ID}")
CLIENT_UUID=$(http_body "$RESP" | jq -r '.[0].id // empty')

if [ -n "$CLIENT_UUID" ]; then
  RESP=$(api PUT "/admin/realms/${KC_REALM}/clients/${CLIENT_UUID}" "$CLIENT_PAYLOAD")
  CODE=$(http_code "$RESP")
  case "$CODE" in
    200|204) echo "  already existed, updated" ;;
    *) echo "##[error]Client update failed (HTTP $CODE)"; http_body "$RESP"; exit 1 ;;
  esac
else
  RESP=$(api POST "/admin/realms/${KC_REALM}/clients" "$CLIENT_PAYLOAD")
  CODE=$(http_code "$RESP")
  if ! created_or_exists "$CODE"; then
    echo "##[error]Client create failed (HTTP $CODE)"
    http_body "$RESP"
    exit 1
  fi
  echo "  created"
  RESP=$(api GET "/admin/realms/${KC_REALM}/clients?clientId=${KC_CLIENT_ID}")
  CLIENT_UUID=$(http_body "$RESP" | jq -r '.[0].id // empty')
fi

if [ -z "$CLIENT_UUID" ]; then
  echo "##[error]Could not resolve the internal id for client ${KC_CLIENT_ID}."
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 4 — realm roles, mapped onto the machine client's service account
# ---------------------------------------------------------------------------
RESP=$(api GET "/admin/realms/${KC_REALM}/clients/${CLIENT_UUID}/service-account-user")
SERVICE_ACCOUNT_ID=$(http_body "$RESP" | jq -r '.id // empty')

if [ -z "$SERVICE_ACCOUNT_ID" ]; then
  echo "##[error]Client ${KC_CLIENT_ID} has no service account user."
  exit 1
fi

IFS=',' read -ra ROLE_ENTRIES <<< "$KC_REALM_ROLES"
for ENTRY in "${ROLE_ENTRIES[@]}"; do
  ROLE_NAME="${ENTRY%%:*}"
  ROLE_DESC="${ENTRY#*:}"
  [ -z "$ROLE_NAME" ] && continue
  [ "$ROLE_DESC" = "$ROLE_NAME" ] && ROLE_DESC=""

  upsert_realm_role "$ROLE_NAME" "$ROLE_DESC"
  ROLE_ID=$(realm_role_id "$ROLE_NAME")
  map_role_to_user "$SERVICE_ACCOUNT_ID" "$ROLE_NAME" "$ROLE_ID" "$KC_CLIENT_ID"
done

# ---------------------------------------------------------------------------
# Step 5 — audit logging
# ---------------------------------------------------------------------------
echo "Audit logging"

RESP=$(api GET "/admin/serverinfo")
EVENT_TYPES=$(http_body "$RESP" | jq -c '.enums.eventType // empty')

if [ -z "$EVENT_TYPES" ] || [ "$EVENT_TYPES" = "null" ]; then
  echo "##[error]Could not read the supported event types from /admin/serverinfo."
  exit 1
fi

EVENT_COUNT=$(printf '%s' "$EVENT_TYPES" | jq 'length')

EVENTS_PAYLOAD=$(jq -nc \
  --argjson types "$EVENT_TYPES" \
  --argjson expiration "$KC_EVENTS_EXPIRATION" \
  '{
     eventsEnabled: true,
     eventsExpiration: $expiration,
     adminEventsEnabled: true,
     adminEventsDetailsEnabled: true,
     eventsListeners: ["jboss-logging"],
     enabledEventTypes: $types
   }')

RESP=$(api PUT "/admin/realms/${KC_REALM}/events/config" "$EVENTS_PAYLOAD")
CODE=$(http_code "$RESP")
case "$CODE" in
  200|204)
    echo "  user events    : enabled"
    echo "  admin events   : enabled, with representation"
    echo "  event types    : all (${EVENT_COUNT})"
    echo "  retention      : ${KC_EVENTS_EXPIRATION}s"
    ;;
  *)
    echo "##[error]Audit configuration failed (HTTP $CODE)"
    http_body "$RESP"
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Step 6 — UI client (browser login enabled), plus its own realm role mapping
# ---------------------------------------------------------------------------
echo ""
echo "UI Client: ${KC_UI_CLIENT_ID} (browser login enabled)"

# Confidential client with a browser leg: standard flow on, service accounts
# also on so its own service-account user exists for the role mappings below.
# Shared by every DPN UI (Kafka UI, Airflow, OpenSearch Dashboards, Jaeger,
# Perses, the portal) — each sits behind its own oauth2-proxy sidecar on the
# shared dpn-observability service (one port per UI) and callbacks at
# "/oauth2/callback". Perses also needs its own native OAuth callback, and
# OpenSearch Dashboards its native OIDC login path.
#
# kafkaUi and kafkaUi2's extra "/login/oauth2/code/keycloak" entries are
# Kafka UI native OIDC login (health-monitoring's dpn-kafka-health-ui and
# dpn-platform's instance, respectively — RBAC-enabled in
# dpn-health-monitoring-service's feature/kafka-ui-role branch and
# dpn-federator-gateway's feature/kafka-ui-authorization-role branch) —
# separate from the oauth2-proxy callback on the same host:port, which still
# fronts both for network-level gating.
UI_CLIENT_PAYLOAD=$(jq -nc \
  --arg clientId "$KC_UI_CLIENT_ID" \
  --arg name "$KC_UI_CLIENT_NAME" \
  --arg description "$KC_UI_CLIENT_DESCRIPTION" \
  --arg secret "$KC_SERVICE_CLIENT_SECRET" \
  --arg kafkaUi "$KC_UI_HOST_KAFKA_UI" \
  --arg kafkaUi2 "$KC_UI_HOST_KAFKA_UI_2" \
  --arg airflow "$KC_UI_HOST_AIRFLOW" \
  --arg jaeger "$KC_UI_HOST_JAEGER" \
  --arg perses "$KC_UI_HOST_PERSES" \
  --arg opensearchDashboards "$KC_UI_HOST_OPENSEARCH_DASHBOARDS" \
  --arg portal "$KC_UI_HOST_PORTAL" \
  --arg federatorClient1 "$KC_UI_HOST_FEDERATOR_CLIENT_1" \
  --arg federatorClient2 "$KC_UI_HOST_FEDERATOR_CLIENT_2" \
  '{
     clientId: $clientId,
     name: $name,
     description: $description,
     enabled: true,
     protocol: "openid-connect",
     secret: $secret,
     frontchannelLogout: true,
     redirectUris: [
       ("https://" + $kafkaUi + "/oauth2/callback"),
       ("https://" + $kafkaUi + "/login/oauth2/code/keycloak"),
       ("https://" + $kafkaUi2 + "/*"),
 #      ("https://" + $kafkaUi2 + "/login/oauth2/code/keycloak"),
       ("https://" + $airflow + "/*"),
 #      ("https://" + $airflow + "/oauth-authorized/keycloak"),
       ("https://" + $opensearchDashboards + "/oauth2/callback"),
       ("https://" + $jaeger + "/oauth2/callback"),
       ("https://" + $perses + "/oauth2/callback"),
       ("https://" + $portal + "/oauth2/callback"),
       ("https://" + $perses + "/api/auth/providers/oauth/keycloak/callback"),
       ("https://" + $opensearchDashboards + "/auth/openid/login"),
       ("https://" + $federatorClient1 + "/*"),
       ("https://" + $federatorClient2 + "/*")
     ],
     webOrigins: [
       ("https://" + $kafkaUi),
       ("https://" + $kafkaUi2),
       ("https://" + $airflow),
       ("https://" + $opensearchDashboards),
       ("https://" + $jaeger),
       ("https://" + $perses),
       ("https://" + $portal),
       ("https://" + $federatorClient1),
       ("https://" + $federatorClient2)
     ],
     defaultClientScopes: ["acr", "roles", "profile", "email"],
     attributes: {
       "post.logout.redirect.uris": ("https://" + $portal + "##https://" + $opensearchDashboards + "##https://" + $jaeger + "##https://" + $perses),
       "backchannel.logout.session.required": "false",
       "backchannel.logout.revoke.offline.tokens": "false"
     },
     publicClient: false,
     standardFlowEnabled: true,
     implicitFlowEnabled: false,
     directAccessGrantsEnabled: false,
     serviceAccountsEnabled: true
   }')

RESP=$(api GET "/admin/realms/${KC_REALM}/clients?clientId=${KC_UI_CLIENT_ID}")
UI_CLIENT_UUID=$(http_body "$RESP" | jq -r '.[0].id // empty')

if [ -n "$UI_CLIENT_UUID" ]; then
  RESP=$(api PUT "/admin/realms/${KC_REALM}/clients/${UI_CLIENT_UUID}" "$UI_CLIENT_PAYLOAD")
  CODE=$(http_code "$RESP")
  case "$CODE" in
    200|204) echo "  already existed, updated" ;;
    *) echo "##[error]UI client update failed (HTTP $CODE)"; http_body "$RESP"; exit 1 ;;
  esac
else
  RESP=$(api POST "/admin/realms/${KC_REALM}/clients" "$UI_CLIENT_PAYLOAD")
  CODE=$(http_code "$RESP")
  if ! created_or_exists "$CODE"; then
    echo "##[error]UI client create failed (HTTP $CODE)"
    http_body "$RESP"
    exit 1
  fi
  echo "  created"
  RESP=$(api GET "/admin/realms/${KC_REALM}/clients?clientId=${KC_UI_CLIENT_ID}")
  UI_CLIENT_UUID=$(http_body "$RESP" | jq -r '.[0].id // empty')
fi

if [ -z "$UI_CLIENT_UUID" ]; then
  echo "##[error]Could not resolve the internal id for client ${KC_UI_CLIENT_ID}."
  exit 1
fi

# Audience mapper — without it, tokens issued by other clients in this realm
# do not carry ${KC_UI_CLIENT_ID} in "aud", and resource servers validating
# that claim reject them. Carried on both the ID and access token, matching
# how the UIs consume it.
echo "Protocol mapper: aud-${KC_UI_CLIENT_ID}"
AUD_MAPPER_PAYLOAD=$(jq -nc --arg name "aud-${KC_UI_CLIENT_ID}" --arg aud "$KC_UI_CLIENT_ID" \
  '{
     name: $name,
     protocol: "openid-connect",
     protocolMapper: "oidc-audience-mapper",
     config: {
       "included.client.audience": $aud,
       "id.token.claim": "true",
       "access.token.claim": "true"
     }
   }')
upsert_protocol_mapper "$UI_CLIENT_UUID" "aud-${KC_UI_CLIENT_ID}" "$AUD_MAPPER_PAYLOAD"

# Realm-role claim mappers — the apps behind this client (e.g. the
# oauth2-proxy-fronted observability UIs) authorize on a role/group claim in
# the token. Emitted as both "roles" and "groups" since which one a given
# proxy reads varies, and both cost nothing to include.
echo "Protocol mapper: realm-roles-claim"
ROLES_MAPPER_PAYLOAD=$(jq -nc \
  '{
     name: "realm-roles-claim",
     protocol: "openid-connect",
     protocolMapper: "oidc-usermodel-realm-role-mapper",
     config: {
       "claim.name": "roles",
       "jsonType.label": "String",
       "multivalued": "true",
       "id.token.claim": "true",
       "access.token.claim": "true",
       "userinfo.token.claim": "true"
     }
   }')
upsert_protocol_mapper "$UI_CLIENT_UUID" "realm-roles-claim" "$ROLES_MAPPER_PAYLOAD"

echo "Protocol mapper: groups-claim"
GROUPS_MAPPER_PAYLOAD=$(jq -nc \
  '{
     name: "groups-claim",
     protocol: "openid-connect",
     protocolMapper: "oidc-usermodel-realm-role-mapper",
     config: {
       "claim.name": "groups",
       "jsonType.label": "String",
       "multivalued": "true",
       "id.token.claim": "true",
       "access.token.claim": "true",
       "userinfo.token.claim": "true"
     }
   }')
upsert_protocol_mapper "$UI_CLIENT_UUID" "groups-claim" "$GROUPS_MAPPER_PAYLOAD"

# No role mapping onto this client's own service account, unlike KC_CLIENT_ID
# above — dpn-realm.json never attached roles to dpn-service-client directly,
# only via group membership (Step 7 below). This client's service account is
# a bare credential (e.g. Kafka UI's SASL_OAUTHBEARER connection to the
# brokers); the roles/groups claims that matter for browser logins come from
# whichever human user is actually signed in, via the protocol mappers above.
echo "UI client configuration complete: client ${KC_UI_CLIENT_ID}."

# ---------------------------------------------------------------------------
# Step 7 — groups, each carrying one realm role
# ---------------------------------------------------------------------------
# Realm roles alone have no entry in the Admin Console's "Groups" tab and
# can't be handed out by adding a user to something — a group wraps a role so
# access can be managed by membership (add/remove a user from dpn-admins)
# instead of assigning the raw role directly on every user.
echo ""
echo "Groups"

IFS=',' read -ra GROUP_ENTRIES <<< "$KC_GROUPS"
for ENTRY in "${GROUP_ENTRIES[@]}"; do
  GROUP_NAME="${ENTRY%%:*}"
  ROLE_NAME="${ENTRY#*:}"
  [ -z "$GROUP_NAME" ] && continue

  echo "Group: ${GROUP_NAME} (role: ${ROLE_NAME})"
  GROUP_PAYLOAD=$(jq -nc --arg name "$GROUP_NAME" '{name: $name}')

  RESP=$(api GET "/admin/realms/${KC_REALM}/groups?search=${GROUP_NAME}&exact=true")
  GROUP_ID=$(http_body "$RESP" | jq -r --arg name "$GROUP_NAME" '.[] | select(.name == $name) | .id // empty')

  if [ -z "$GROUP_ID" ]; then
    RESP=$(api POST "/admin/realms/${KC_REALM}/groups" "$GROUP_PAYLOAD")
    CODE=$(http_code "$RESP")
    if ! created_or_exists "$CODE"; then
      echo "##[error]Group create failed (HTTP $CODE)"
      http_body "$RESP"
      exit 1
    fi
    echo "  created"
    RESP=$(api GET "/admin/realms/${KC_REALM}/groups?search=${GROUP_NAME}&exact=true")
    GROUP_ID=$(http_body "$RESP" | jq -r --arg name "$GROUP_NAME" '.[] | select(.name == $name) | .id // empty')
  else
    echo "  already existed"
  fi

  if [ -z "$GROUP_ID" ]; then
    echo "##[error]Could not resolve id for group ${GROUP_NAME}."
    exit 1
  fi

  ROLE_ID=$(realm_role_id "$ROLE_NAME")

  MAPPING_PAYLOAD=$(jq -nc --arg id "$ROLE_ID" --arg name "$ROLE_NAME" '[{id: $id, name: $name}]')
  RESP=$(api POST "/admin/realms/${KC_REALM}/groups/${GROUP_ID}/role-mappings/realm" "$MAPPING_PAYLOAD")
  CODE=$(http_code "$RESP")
  case "$CODE" in
    200|204) echo "  role ${ROLE_NAME} attached" ;;
    *) echo "##[error]Group role mapping failed (HTTP $CODE)"; http_body "$RESP"; exit 1 ;;
  esac
done

echo "Groups configuration complete."
echo ""
echo "Keycloak configuration complete: realm ${KC_REALM}, clients ${KC_CLIENT_ID} + ${KC_UI_CLIENT_ID}."
