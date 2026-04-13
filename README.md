# BasicTodo

Application iOS SwiftUI minimale pour gérer des tâches, avec un assistant IA local-only reposant exclusivement sur Apple Foundation Models lorsque le modèle on-device est disponible.

## Arborescence

```text
BasicTodo.xcodeproj
BasicTodo/
  BasicTodoApp.swift
  AppContainer.swift
  Models/
    TaskItem.swift
    ChatMessage.swift
  Repositories/
    TaskRepository.swift
    JSONTaskRepository.swift
  UseCases/
    TaskManaging.swift
    DefaultTaskService.swift
  Services/
    Assistant/
      TaskAssistantService.swift
    Speech/
      LocalSpeechTranscriptionService.swift
  ViewModels/
    TaskListViewModel.swift
    AIChatViewModel.swift
  Views/
    TaskListView.swift
    AIChatView.swift
    Components/
      TaskRowView.swift
      TaskComposerView.swift
      TaskEditorSheet.swift
  Resources/
    Assets.xcassets/
```

## IA locale uniquement

- L’app n’utilise que `SystemLanguageModel.default` du framework Apple `FoundationModels`.
- La saisie vocale utilise `Speech` en mode on-device uniquement, sans fallback réseau.
- Si le modèle on-device est indisponible, l’interface IA reste désactivée avec un message explicite.
- Aucun backend, aucune API externe, aucune clé d’API et aucun fallback distant ne sont ajoutés.
# SmartToDoTest
