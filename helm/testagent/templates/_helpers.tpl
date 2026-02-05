{{/*
通用帮助模板
*/}}

{{/* 生成全名 */}}
{{- define "testagent.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* 生成名称 */}}
{{- define "testagent.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* 生成 Chart 名称和版本 */}}
{{- define "testagent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* 通用标签 */}}
{{- define "testagent.labels" -}}
helm.sh/chart: {{ include "testagent.chart" . }}
{{ include "testagent.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* 选择器标签 */}}
{{- define "testagent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "testagent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* 服务账户名称 */}}
{{- define "testagent.serviceAccountName" -}}
{{- printf "%s-sa" (include "testagent.fullname" .) -}}
{{- end -}}

{{/* 数据库连接字符串 */}}
{{- define "testagent.database.url" -}}
{{- if .Values.postgresql.external.enabled -}}
{{- printf "postgresql://%s:%s@%s:%d/%s" 
    .Values.postgresql.external.username
    .Values.postgresql.external.password
    .Values.postgresql.external.host
    (.Values.postgresql.external.port | int)
    .Values.postgresql.external.database -}}
{{- else -}}
{{- printf "postgresql://%s:%s@%s-postgresql:5432/%s"
    .Values.postgresql.auth.username
    .Values.postgresql.auth.password
    .Release.Name
    .Values.postgresql.auth.database -}}
{{- end -}}
{{- end -}}

{{/* Redis 连接字符串 */}}
{{- define "testagent.redis.url" -}}
{{- if .Values.redis.external.enabled -}}
{{- if .Values.redis.external.password -}}
{{- printf "redis://:%s@%s:%d" .Values.redis.external.password .Values.redis.external.host (.Values.redis.external.port | int) -}}
{{- else -}}
{{- printf "redis://%s:%d" .Values.redis.external.host (.Values.redis.external.port | int) -}}
{{- end -}}
{{- else -}}
{{- printf "redis://%s-redis:6379" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/* 镜像仓库地址 */}}
{{- define "testagent.imageRegistry" -}}
{{- if .Values.global.imageRegistry -}}
{{- printf "%s/" .Values.global.imageRegistry -}}
{{- end -}}
{{- end -}}
