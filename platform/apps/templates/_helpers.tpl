{{/* Common Application metadata. Args: name, wave, finalizer(bool, default true) */}}
{{- define "platform.meta" -}}
name: {{ .name }}
namespace: argocd
annotations:
  argocd.argoproj.io/sync-wave: {{ .wave | quote }}
{{- if (ne (toString .finalizer) "false") }}
finalizers:
  - resources-finalizer.argocd.argoproj.io
{{- end }}
{{- end }}

{{- define "platform.syncPolicy" -}}
automated:
  prune: true
  selfHeal: true
syncOptions:
  - CreateNamespace=true
  - ServerSideApply=true
  - SkipDryRunOnMissingResource=true
managedNamespaceMetadata:
  labels:
    owner: platform
retry:
  limit: 10
  backoff:
    duration: 30s
    factor: 2
    maxDuration: 10m
{{- end }}

{{- define "platform.destination" -}}
server: https://kubernetes.default.svc
namespace: {{ . }}
{{- end }}

{{/* Git repo as the "$values" source for value files */}}
{{- define "platform.valuesSource" -}}
- repoURL: {{ .Values.repoURL }}
  targetRevision: {{ .Values.targetRevision }}
  ref: values
{{- end }}

{{- define "platform.url" -}}
http://{{ .host }}.{{ .root.Values.cluster.domain }}
{{- end }}

{{/* JMESPath list literal: ['a@x', 'b@y'] */}}
{{- define "platform.jmesList" -}}
[{{- range $i, $e := . }}{{ if $i }}, {{ end }}'{{ $e }}'{{- end }}]
{{- end }}

{{- define "platform.allUsers" -}}
{{- join "\n" (concat .Values.auth.admins .Values.auth.viewers | uniq) -}}
{{- end }}
