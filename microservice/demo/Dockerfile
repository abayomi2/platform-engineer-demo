# microservice/Dockerfile
# Use a JRE base image for smaller size
FROM openjdk:17-slim-buster
# Set the working directory
WORKDIR /app

# Copy the JAR file (build it first using Maven)
# The JAR will be named target/demo-0.0.1-SNAPSHOT.jar (adjust version if needed)
COPY target/demo-0.0.1-SNAPSHOT.jar app.jar

# Expose the port Spring Boot runs on
EXPOSE 8080

# Command to run the application
ENTRYPOINT ["java", "-jar", "app.jar"]