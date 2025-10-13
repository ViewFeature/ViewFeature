import SwiftUI

struct ContentView: View {
  var body: some View {
    NavigationStack {
      List {
        Section("Basic Examples") {
          NavigationLink("Counter") {
            CounterView()
          }

          NavigationLink("Todo List") {
            TodoView()
          }
        }

        Section("Advanced Examples") {
          NavigationLink("User Management") {
            UserView()
          }
        }
      }
      .navigationTitle("ViewFeature Demo")
    }
  }
}

#Preview {
  ContentView()
}
