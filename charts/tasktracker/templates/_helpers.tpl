{{/*
=============================================================================
File        : charts/tasktracker/templates/_helpers.tpl
Assignment  : DSO202 Assignment 4 (chart from Assignment 3)
Descriptor  : Unit III 3.2 - Helm named templates
Purpose     : Labels shared by every object the chart renders. Selector labels
              are written in each template, because they differ per tier and
              must never change after a Deployment is created.
=============================================================================
*/}}

{{- define "tasktracker.labels" -}}
app.kubernetes.io/name: tasktracker
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
