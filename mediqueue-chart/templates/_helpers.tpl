{{/*
Expand the name of the chart.
*/}}
{{- define "mediqueue-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mediqueue-chart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mediqueue-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Namespace to use
*/}}
{{- define "mediqueue-chart.namespace" -}}
{{- if .Values.namespace.create }}
{{- .Values.namespace.name | default .Release.Namespace }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mediqueue-chart.labels" -}}
helm.sh/chart: {{ include "mediqueue-chart.chart" . }}
{{ include "mediqueue-chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.podLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mediqueue-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mediqueue-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component-specific labels
*/}}
{{- define "mediqueue-chart.componentLabels" -}}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "mediqueue-chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mediqueue-chart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Frontend name
*/}}
{{- define "mediqueue-chart.frontend.fullname" -}}
{{- printf "%s-frontend" (include "mediqueue-chart.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
API name
*/}}
{{- define "mediqueue-chart.api.fullname" -}}
{{- printf "%s-api" (include "mediqueue-chart.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Worker name
*/}}
{{- define "mediqueue-chart.worker.fullname" -}}
{{- printf "%s-worker" (include "mediqueue-chart.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
PostgreSQL name
*/}}
{{- define "mediqueue-chart.postgres.fullname" -}}
{{- printf "%s-postgres" (include "mediqueue-chart.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
PostgreSQL host
*/}}
{{- define "mediqueue-chart.postgres.host" -}}
{{- printf "%s-0.%s.%s.svc.cluster.local" (include "mediqueue-chart.postgres.fullname" .) (include "mediqueue-chart.postgres.fullname" .) (include "mediqueue-chart.namespace" .) }}
{{- end }}

{{/*
PostgreSQL URL (without password - use secret mounting)
*/}}
{{- define "mediqueue-chart.postgres.url" -}}
{{- printf "postgres://%s:$(POSTGRES_PASSWORD)@%s:%v/%s" .Values.postgres.auth.username (include "mediqueue-chart.postgres.host" .) .Values.postgres.service.port .Values.postgres.auth.database }}
{{- end }}

{{/*
Redis name
*/}}
{{- define "mediqueue-chart.redis.fullname" -}}
{{- printf "%s-redis" (include "mediqueue-chart.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Redis host
*/}}
{{- define "mediqueue-chart.redis.host" -}}
{{- printf "%s-0.%s.%s.svc.cluster.local" (include "mediqueue-chart.redis.fullname" .) (include "mediqueue-chart.redis.fullname" .) (include "mediqueue-chart.namespace" .) }}
{{- end }}

{{/*
Redis URL
*/}}
{{- define "mediqueue-chart.redis.url" -}}
{{- if .Values.redis.auth.enabled }}
{{- printf "redis://:$(REDIS_PASSWORD)@%s:%v" (include "mediqueue-chart.redis.host" .) .Values.redis.service.port }}
{{- else }}
{{- printf "redis://%s:%v" (include "mediqueue-chart.redis.host" .) .Values.redis.service.port }}
{{- end }}
{{- end }}

{{/*
PostgreSQL secret name
*/}}
{{- define "mediqueue-chart.postgres.secretName" -}}
{{- if .Values.postgres.auth.existingSecret }}
{{- .Values.postgres.auth.existingSecret }}
{{- else }}
{{- printf "%s-postgres" (include "mediqueue-chart.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Redis secret name
*/}}
{{- define "mediqueue-chart.redis.secretName" -}}
{{- if .Values.redis.auth.existingSecret }}
{{- .Values.redis.auth.existingSecret }}
{{- else }}
{{- printf "%s-redis" (include "mediqueue-chart.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Image pull secrets
*/}}
{{- define "mediqueue-chart.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Get image tag
*/}}
{{- define "mediqueue-chart.imageTag" -}}
{{- .tag | default $.Values.global.imageTag | default "latest" }}
{{- end }}

{{/*
Common pod annotations
*/}}
{{- define "mediqueue-chart.podAnnotations" -}}
{{- with .Values.podAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}
