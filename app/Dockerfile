FROM eclipse-temurin:17-jre
WORKDIR /work
COPY target/quarkus-app/ /work/
EXPOSE 8080
CMD ["java", "-jar", "quarkus-run.jar"]
