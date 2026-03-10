FROM node:20-slim

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Build argument for API URL (used at build time)
ARG VITE_PUBLIC_API_URL=""
ENV VITE_PUBLIC_API_URL=$VITE_PUBLIC_API_URL

# Build the app
RUN npm run build

# Environment variables for runtime
ENV NODE_ENV=production
ENV ORIGIN=http://localhost:3000

# Expose port
EXPOSE 3000

# Start the app
CMD ["node", "build"]
