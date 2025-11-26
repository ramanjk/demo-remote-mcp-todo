param name string
param exists bool

resource existingContainerApp 'Microsoft.App/containerApps@2024-03-01' existing = if (exists) {
  name: name
}

output containers array = exists ? existingContainerApp.?properties.?template.?containers ?? [] : []
