FROM alpine:3.20
RUN apk add --no-cache tzdata ca-certificates
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
WORKDIR /app
COPY nimbus-blog-api/dist/nimbus-blog-api /app/nimbus-blog-api
RUN chmod 0755 /app/nimbus-blog-api
EXPOSE 8080
USER nobody
ENTRYPOINT ["/app/nimbus-blog-api"]
