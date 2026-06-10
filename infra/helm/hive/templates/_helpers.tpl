{{- define "hive.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hive.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "hive.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "hive.labels" -}}
app.kubernetes.io/name: {{ include "hive.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "hive.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hive.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "hive.webSelectorLabels" -}}
{{ include "hive.selectorLabels" . }}
app.kubernetes.io/component: web
{{- end -}}

{{- define "hive.appSecretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{ .Values.secrets.existingSecret }}
{{- else -}}
{{ include "hive.fullname" . }}-app
{{- end -}}
{{- end -}}

{{- define "hive.postgresClusterName" -}}
{{ include "hive.fullname" . }}-postgres
{{- end -}}

{{- define "hive.postgresAppSecret" -}}
{{ include "hive.postgresClusterName" . }}-app
{{- end -}}

{{- define "hive.vectorName" -}}
{{ include "hive.fullname" . }}-vector
{{- end -}}

{{- define "hive.vectorLabels" -}}
{{ include "hive.labels" . }}
app.kubernetes.io/component: vector
{{- end -}}

{{- define "hive.vectorSelectorLabels" -}}
{{ include "hive.selectorLabels" . }}
app.kubernetes.io/component: vector
{{- end -}}

{{- define "hive.conduktSandboxNamespace" -}}
{{- default (printf "%s-condukt-sandbox" (include "hive.fullname" .)) .Values.conduktSandbox.namespace -}}
{{- end -}}

{{- define "hive.conduktSandboxServiceAccountName" -}}
{{- default (printf "%s-condukt-sandbox" (include "hive.fullname" .)) .Values.conduktSandbox.serviceAccount.name -}}
{{- end -}}

{{- define "hive.conduktSandboxImage" -}}
{{- printf "%s:%s" .Values.conduktSandbox.image.repository (.Values.conduktSandbox.image.tag | default "latest") -}}
{{- end -}}

{{- define "hive.conduktSandboxEnv" -}}
{{- if .Values.conduktSandbox.enabled }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX") }}
- name: HIVE_CONDUKT_SANDBOX
  value: "kubernetes"
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_NAMESPACE") }}
- name: HIVE_CONDUKT_SANDBOX_NAMESPACE
  value: {{ include "hive.conduktSandboxNamespace" . | quote }}
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_IMAGE") }}
- name: HIVE_CONDUKT_SANDBOX_IMAGE
  value: {{ include "hive.conduktSandboxImage" . | quote }}
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_SERVICE_ACCOUNT") }}
- name: HIVE_CONDUKT_SANDBOX_SERVICE_ACCOUNT
  value: {{ include "hive.conduktSandboxServiceAccountName" . | quote }}
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_ACTIVE_DEADLINE_SECONDS") }}
- name: HIVE_CONDUKT_SANDBOX_ACTIVE_DEADLINE_SECONDS
  value: {{ .Values.conduktSandbox.pod.activeDeadlineSeconds | quote }}
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_READY_TIMEOUT_MS") }}
- name: HIVE_CONDUKT_SANDBOX_READY_TIMEOUT_MS
  value: {{ .Values.conduktSandbox.pod.readyTimeoutMilliseconds | quote }}
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_HEARTBEAT_INTERVAL_MS") }}
- name: HIVE_CONDUKT_SANDBOX_HEARTBEAT_INTERVAL_MS
  value: {{ .Values.conduktSandbox.pod.heartbeatIntervalMilliseconds | quote }}
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_CPU_REQUEST") }}
- name: HIVE_CONDUKT_SANDBOX_CPU_REQUEST
  value: {{ .Values.conduktSandbox.pod.resources.requests.cpu | quote }}
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_MEMORY_REQUEST") }}
- name: HIVE_CONDUKT_SANDBOX_MEMORY_REQUEST
  value: {{ .Values.conduktSandbox.pod.resources.requests.memory | quote }}
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_CPU_LIMIT") }}
- name: HIVE_CONDUKT_SANDBOX_CPU_LIMIT
  value: {{ .Values.conduktSandbox.pod.resources.limits.cpu | quote }}
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_MEMORY_LIMIT") }}
- name: HIVE_CONDUKT_SANDBOX_MEMORY_LIMIT
  value: {{ .Values.conduktSandbox.pod.resources.limits.memory | quote }}
{{- end }}
{{- if not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_NETWORK_POLICY") }}
- name: HIVE_CONDUKT_SANDBOX_NETWORK_POLICY
  value: {{ .Values.conduktSandbox.networkPolicy.enabled | quote }}
{{- end }}
{{- if and .Values.conduktSandbox.networkPolicy.enabled (not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_NETWORK_POLICY_ALLOW")) }}
- name: HIVE_CONDUKT_SANDBOX_NETWORK_POLICY_ALLOW
  value: {{ join "," .Values.conduktSandbox.networkPolicy.allowedHosts | quote }}
{{- end }}
{{- if and .Values.conduktSandbox.networkPolicy.image (not (hasKey .Values.env "HIVE_CONDUKT_SANDBOX_NETWORK_POLICY_IMAGE")) }}
- name: HIVE_CONDUKT_SANDBOX_NETWORK_POLICY_IMAGE
  value: {{ .Values.conduktSandbox.networkPolicy.image | quote }}
{{- end }}
{{- end }}
{{- end -}}
