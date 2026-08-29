FROM dart:3.3

WORKDIR /app
COPY . .

RUN dart pub get

EXPOSE 8080

CMD ["dart", "run", "bin/server.dart"]
