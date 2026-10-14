{{/* Nom court du chart */}}
{{- define "taskapi.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Nom complet des ressources. Si le nom de la release contient déjà le nom du chart,
on ne le répète pas (release "taskapi" → "taskapi", release "demo" → "demo-taskapi").
Limité à 63 caractères (contrainte des noms DNS Kubernetes).
*/}}
{{- define "taskapi.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Labels de sélection : NE DOIVENT JAMAIS CHANGER après la 1re installation (selector immuable) */}}
{{- define "taskapi.selectorLabels" -}}
app.kubernetes.io/name: {{ include "taskapi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Labels communs recommandés */}}
{{- define "taskapi.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "taskapi.selectorLabels" . }}
app.kubernetes.io/version: {{ (.Values.image.tag | default .Chart.AppVersion) | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: devops-bootcamp
{{- end -}}

{{- define "taskapi.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}
