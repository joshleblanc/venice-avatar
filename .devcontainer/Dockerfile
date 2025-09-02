FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Install system dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        # Build tools
        build-essential \
        git \
        curl \
        wget \
        # Ruby dependencies
        libyaml-dev \
        libssl-dev \
        libreadline-dev \
        zlib1g-dev \
        libncurses5-dev \
        libffi-dev \
        libgdbm-dev \
        # SQLite
        sqlite3 \
        libsqlite3-dev \
        # Image processing
        imagemagick \
        libmagickwand-dev \
        # Node.js for asset pipeline
        nodejs \
        npm \
        # Additional utilities
        vim \
        less \
        htop \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install rbenv and Ruby 3.4.4
USER vscode
RUN git clone https://github.com/rbenv/rbenv.git ~/.rbenv \
    && echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc \
    && echo 'eval "$(rbenv init -)"' >> ~/.bashrc \
    && git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

# Install Ruby 3.4.4
RUN export PATH="$HOME/.rbenv/bin:$PATH" \
    && eval "$(rbenv init -)" \
    && rbenv install 3.4.4 \
    && rbenv global 3.4.4 \
    && rbenv rehash

# Install Bundler
RUN export PATH="$HOME/.rbenv/bin:$PATH" \
    && eval "$(rbenv init -)" \
    && gem install bundler

# Set working directory
WORKDIR /workspaces/venice-avatar

# Copy Gemfile and install gems (this will be done when container starts)
# The actual bundle install will happen in postCreateCommand
