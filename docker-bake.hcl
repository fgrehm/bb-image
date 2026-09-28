# CI builds each Containerfile against the result of its parent target. The
# internal targets are never pushed. Local podman uses build/build.sh instead.
# CI reads these pins from Containerfile.foundation into its environment.
variable "BB_VERSION" {
  default = ""
}

variable "BB_NODE_VERSION" {
  default = ""
}

variable "PLAYWRIGHT_VERSION" {
  default = ""
}

target "_common" {
  context = "."
  secret  = ["id=github_token,env=GH_TOKEN"]
  args = {
    BB_VERSION         = BB_VERSION
    BB_NODE_VERSION    = BB_NODE_VERSION
    PLAYWRIGHT_VERSION = PLAYWRIGHT_VERSION
    USERNAME           = "developer"
    BUILD_SCRATCH      = "/tmp/build-scratch"
  }
}

target "foundation" {
  inherits   = ["_common"]
  dockerfile = "container/Containerfile.foundation"
}

target "full" {
  inherits   = ["_common"]
  dockerfile = "container/Containerfile.full"
  contexts   = { parent = "target:foundation" }
  args       = { BASE_IMAGE = "parent" }
}

target "slim" {
  inherits   = ["_common"]
  dockerfile = "container/Containerfile.slim"
  contexts   = { parent = "target:foundation" }
  args       = { BASE_IMAGE = "parent" }
}

target "worker" {
  inherits   = ["_common"]
  dockerfile = "container/Containerfile.worker"
  contexts   = { parent = "target:foundation" }
  args       = { BASE_IMAGE = "parent" }
}

target "slim-sudo" {
  inherits   = ["_common"]
  dockerfile = "container/Containerfile.slim-sudo"
  contexts   = { parent = "target:slim" }
  args       = { BASE_IMAGE = "parent" }
}

target "full-sudo" {
  inherits   = ["_common"]
  dockerfile = "container/Containerfile.full-sudo"
  contexts   = { parent = "target:full" }
  args       = { BASE_IMAGE = "parent" }
}

target "vm" {
  inherits   = ["_common"]
  dockerfile = "container/Containerfile.vm"
  contexts   = { parent = "target:full" }
  args       = { BASE_IMAGE = "parent" }
}

target "vm-sudo" {
  inherits   = ["_common"]
  dockerfile = "container/Containerfile.vm-sudo"
  contexts   = { parent = "target:vm" }
  args       = { BASE_IMAGE = "parent" }
}

target "exedev" {
  inherits   = ["_common"]
  dockerfile = "container/Containerfile.exedev"
  contexts   = { parent = "target:vm" }
  args       = { BASE_IMAGE = "parent" }
}

target "worker-vm" {
  inherits   = ["_common"]
  dockerfile = "container/Containerfile.worker-vm"
  contexts   = { parent = "target:worker" }
  args       = { BASE_IMAGE = "parent" }
}
