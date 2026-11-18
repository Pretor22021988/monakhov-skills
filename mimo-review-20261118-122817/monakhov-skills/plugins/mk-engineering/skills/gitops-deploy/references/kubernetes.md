# GitOps в Kubernetes: Argo CD и Flux

Оператор внутри кластера сам сравнивает состояние кластера с git и выравнивает
его. Человек меняет только репозиторий.

## Минимальное приложение Argo CD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/OWNER/REPO.git
    targetRevision: v1.4.0        # тег, а не HEAD: версия однозначна
    path: deploy/overlays/prod     # kustomize-оверлей окружения
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true                  # удалять то, чего нет в git
      selfHeal: true               # откатывать ручные правки в кластере (дрейф)
```

## Структура репозитория

```
deploy/
  base/                 # общие манифесты
  overlays/
    staging/            # отличия окружений — только патчи
    prod/
```

## Flux — то же самое другим инструментом

`GitRepository` (откуда брать) + `Kustomization` (что применять, `prune: true`).
Выбор между Argo CD и Flux — вопрос удобства: у Argo CD веб-интерфейс, Flux легче
и целиком декларативен.

## Откат

Перевести `targetRevision` на предыдущий тег коммитом. Кнопка «rollback» в
интерфейсе Argo CD при включённом `automated` будет перезаписана синхронизацией —
откатывай через git.
