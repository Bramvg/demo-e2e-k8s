package org.example;

import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.event.Observes;

public class ApplicationLifecycle {

    void onStart(@Observes StartupEvent ev) {
        System.out.println("🚀 Quarkus application started");
    }
}
