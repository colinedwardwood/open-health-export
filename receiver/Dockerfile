# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

FROM swift:6.3.3-jammy AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
RUN swift build -c release --product receiver

FROM swift:6.3.3-jammy
COPY --from=build /src/.build/release/receiver /usr/local/bin/receiver
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/receiver"]
CMD ["serve", "--port", "8080"]
