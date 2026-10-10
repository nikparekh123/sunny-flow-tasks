# Theta Terminal v3 behind a key-checked gate, for Sunnyfi's edge functions.
# The Terminal only serves 127.0.0.1; proxy.py is the one door in, on :8080.
FROM eclipse-temurin:21-jre
RUN apt-get update && apt-get install -y --no-install-recommends python3 curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN curl -fsSL -o ThetaTerminalv3.jar https://downloads.thetadata.us/ThetaTerminalv3.jar
COPY proxy.py start.sh ./
EXPOSE 8080
CMD ["sh", "/app/start.sh"]
