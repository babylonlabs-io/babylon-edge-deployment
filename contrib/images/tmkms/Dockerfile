# A custom Dockerfile is needed since an official Docker image is not available.
FROM rust:alpine AS builder

# Install dependencies
RUN apk add --no-cache musl-dev git

# Set the working directory
WORKDIR /tmkms

# Clone the tmkms repository
RUN git clone https://github.com/iqlusioninc/tmkms.git && cd tmkms && cargo install tmkms --features=softsign

# Create a minimal runtime image
FROM alpine:latest

# Install necessary dependencies
RUN apk add --no-cache bash

# Copy the built binary from the builder stage
COPY --from=builder /usr/local/cargo/bin/tmkms /usr/local/bin/tmkms

# Set the default shell as /bin/sh
CMD ["/bin/sh"] 