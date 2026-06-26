# ---- Stage 1: Build ----
FROM eclipse-temurin:21-jdk AS build

WORKDIR /app

COPY gradle/ gradle/
COPY gradlew build.gradle settings.gradle ./
RUN ./gradlew dependencies --no-daemon

COPY src/ src/
RUN ./gradlew build -x test --no-daemon

# ---- Stage 2: Runtime ----
FROM eclipse-temurin:21-jre

WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar

EXPOSE 8761
ENTRYPOINT ["java", "-jar", "app.jar"]
