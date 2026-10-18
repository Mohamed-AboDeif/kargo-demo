{{- define "kargo-demo.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kargo-demo.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kargo-demo.labels" -}}
app.kubernetes.io/name: {{ include "kargo-demo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "kargo-demo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kargo-demo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
