{{/*
Resolved release name — drives every object name, including the ClusterIP
service name callers resolve.
*/}}
{{- define "keycloak.name" -}}
{{- .Values.fullnameOverride | default .Release.Name -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "keycloak.labels" -}}
app.kubernetes.io/name: {{ include "keycloak.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}

{{/*
Selector labels for the Keycloak pods
*/}}
{{- define "keycloak.selectorLabels" -}}
app: {{ include "keycloak.name" . }}
{{- end -}}

{{/*
Selector labels for the bundled PostgreSQL pods
*/}}
{{- define "keycloak.postgres.selectorLabels" -}}
app: {{ .Values.postgres.name }}
{{- end -}}

{{/*
Name of the SecretProviderClass shared by Keycloak and PostgreSQL.
*/}}
{{- define "keycloak.secretProviderClassName" -}}
{{ include "keycloak.name" . }}-kv-secrets
{{- end -}}

{{/*
ServiceAccount the Keycloak and PostgreSQL pods run as. Falls back to "default"
only when creation is disabled and no name is supplied.
*/}}
{{- define "keycloak.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ .Values.serviceAccount.name | default (include "keycloak.name" .) }}
{{- else -}}
{{ .Values.serviceAccount.name | default "default" }}
{{- end -}}
{{- end -}}

{{/*
Fail fast on a configuration that cannot work, rather than letting the pod come
up and fail its TLS handshake or its database connection.
*/}}
{{- define "keycloak.validate" -}}
{{- if not .Values.tlsSecretName -}}
{{- fail "tlsSecretName is empty — set it to the secret holding keystore.jks (e.g. dpn-tls)" -}}
{{- end -}}
{{- if not .Values.config.KC_DB_URL -}}
{{- fail "config.KC_DB_URL is empty" -}}
{{- end -}}
{{- if ne (printf "%v" .Values.config.KC_HTTPS_CLIENT_AUTH) "none" -}}
{{- fail (printf "config.KC_HTTPS_CLIENT_AUTH must be \"none\" for this non-mTLS deployment, got %q" (printf "%v" .Values.config.KC_HTTPS_CLIENT_AUTH)) -}}
{{- end -}}
{{- if ne (printf "%v" .Values.config.KC_HTTP_ENABLED) "false" -}}
{{- fail "config.KC_HTTP_ENABLED must be \"false\" — this deployment is HTTPS only" -}}
{{- end -}}
{{- end -}}
