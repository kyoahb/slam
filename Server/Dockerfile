# Built from the repo root: docker build -f Server/Dockerfile .
FROM swift:6.2-noble AS build
WORKDIR /src
COPY Packages/SlamCore Packages/SlamCore
COPY Server/Package.swift Server/Package.resolved Server/
RUN cd Server && swift package resolve
COPY Server/Sources Server/Sources
COPY Server/Tests Server/Tests
RUN cd Server && swift build -c release --product slam --static-swift-stdlib \
    && cp "$(swift build -c release --show-bin-path)/slam" /slam

FROM ubuntu:noble
COPY --from=build /slam /usr/local/bin/slam
# A new data volume takes this owner.
RUN mkdir /data /backups && chown 1000:1000 /data /backups
USER 1000:1000
EXPOSE 9097
ENTRYPOINT ["slam"]
CMD ["serve"]
