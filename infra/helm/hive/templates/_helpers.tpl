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

{{- define "hive.clickhouseName" -}}
{{ include "hive.fullname" . }}-clickhouse
{{- end -}}

{{- define "hive.clickhouseLabels" -}}
{{ include "hive.labels" . }}
app.kubernetes.io/component: clickhouse
{{- end -}}

{{- define "hive.clickhouseSelectorLabels" -}}
{{ include "hive.selectorLabels" . }}
app.kubernetes.io/component: clickhouse
{{- end -}}

{{- define "hive.clickhouseEnv" -}}
{{- if .Values.clickhouse.enabled }}
- name: HIVE_CLICKHOUSE_ENABLED
  value: "true"
- name: HIVE_CLICKHOUSE_HOST
  value: {{ include "hive.clickhouseName" . | quote }}
- name: HIVE_CLICKHOUSE_PORT
  value: {{ .Values.clickhouse.service.httpPort | quote }}
- name: HIVE_CLICKHOUSE_DATABASE
  value: {{ .Values.clickhouse.database | quote }}
- name: HIVE_CLICKHOUSE_USERNAME
  value: {{ .Values.clickhouse.username | quote }}
{{- end }}
{{- end -}}

{{- define "hive.codingSandboxNamespace" -}}
{{- .Values.codingRuns.kubernetes.namespace | default .Release.Namespace -}}
{{- end -}}

{{- define "hive.codingSandboxServiceAccount" -}}
{{- default (printf "%s-coding-sandbox" (include "hive.fullname" .)) .Values.codingRuns.kubernetes.serviceAccountName -}}
{{- end -}}

{{- define "hive.codingRunsEnv" -}}
{{- if not (hasKey .Values.env "HIVE_CODING_RUNNER") }}
- name: HIVE_CODING_RUNNER
  value: {{ .Values.codingRuns.provider | quote }}
{{- if eq .Values.codingRuns.provider "kubernetes" }}
{{- $options := dict
  "namespace" (include "hive.codingSandboxNamespace" .)
  "in_cluster" .Values.codingRuns.kubernetes.inCluster
  "runtime_class_name" .Values.codingRuns.kubernetes.runtimeClassName
  "service_account" (include "hive.codingSandboxServiceAccount" .)
  "image_pull_policy" .Values.codingRuns.image.pullPolicy
  "ready_timeout_ms" .Values.codingRuns.kubernetes.readyTimeoutMilliseconds
  "node_selector" .Values.codingRuns.kubernetes.nodeSelector
  "tolerations" .Values.codingRuns.kubernetes.tolerations
-}}
{{- if .Values.codingRuns.kubernetes.imagePullSecretName }}
{{- $_ := set $options "image_pull_secrets" (list .Values.codingRuns.kubernetes.imagePullSecretName) -}}
{{- end }}
- name: HIVE_CODING_SANDBOX_OPTIONS
  value: {{ $options | toJson | quote }}
- name: HIVE_CODING_IMAGE
  value: {{ printf "%s:%s" .Values.codingRuns.image.repository .Values.codingRuns.image.tag | quote }}
- name: HIVE_CODING_CPUS
  value: {{ .Values.codingRuns.cpus | quote }}
- name: HIVE_CODING_MEMORY_MIB
  value: {{ .Values.codingRuns.memoryMi | quote }}
- name: HIVE_CODING_DISK_MIB
  value: {{ .Values.codingRuns.diskMi | quote }}
- name: HIVE_CODING_TIMEOUT_MINUTES
  value: {{ .Values.codingRuns.timeoutMinutes | quote }}
{{- if .Values.codingRuns.setupCommand }}
- name: HIVE_CODING_SETUP_COMMAND
  value: {{ .Values.codingRuns.setupCommand | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
