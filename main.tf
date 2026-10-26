terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6.2"
    }
  }
}

provider "docker" {
  host = "npipe:////.//pipe//docker_engine"
}

resource "docker_image" "app" {
  name = "hello-svc:dev"

  build {
    context = path.module
  }
}

resource "docker_container" "app" {
  name  = "hello-svc"
  image = docker_image.app.image_id

  ports {
    internal = 8080
    external = 8080
  }

  restart = "unless-stopped"
}

output "app_url" {
  value = "http://localhost:8080"
}
lo