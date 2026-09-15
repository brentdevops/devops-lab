{{/*
Shared naming and label helpers, so every template agrees on names.
*/}}

{{- define "platform-lab.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Full resource name. When the release is named after the chart (our case:
release "platform-lab", chart "platform-lab") this returns just "platform-lab"
rather than "platform-lab-platform-lab".
*/}}
{{- define "platform-lab.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Selector labels. These go on the pod template AND the Service selector, which
is what guarantees they match. Hand-written YAML is where that mismatch —
and the mysterious 503 it causes — usually creeps in.

Never add version here: selectors are immutable on a Deployment, so a label
that changes per release would make every upgrade fail.
*/}}
{{- define "platform-lab.selectorLabels" -}}
app.kubernetes.io/name: {{ include "platform-lab.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Full label set for metadata. Includes version, which is free to change.
*/}}
{{- define "platform-lab.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "platform-lab.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
