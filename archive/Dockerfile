FROM steamcmd/steamcmd:ubuntu-bionic

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN dpkg --add-architecture i386 && apt update && \
    apt install -y wine-stable winbind xvfb mariadb-server curl gettext

# Add non-root user
RUN useradd -m lifuser

# Set up working directory
WORKDIR /home/lifuser/yoserver

# Expose default server ports
EXPOSE 28000 28001 28002

# Copy init and run scripts
COPY init.sh run.sh ./
RUN chmod +x init.sh run.sh

# Override entrypoint to prevent automatic execution of steamcmd
ENTRYPOINT ["./init.sh"]