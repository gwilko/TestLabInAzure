variable "subnets" {
  type = map(object({
    ip   = string
    name = string
  }))
}