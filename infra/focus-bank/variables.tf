variable "google_client_id" {
  description = "OAuth 2.0 Web client ID from Google Cloud Console; the identity pool's Google login provider."
  type        = string
  default     = "998004519126-rsgaml9bajuaquabvujf76dh5oegej9s.apps.googleusercontent.com"

  validation {
    condition     = endswith(var.google_client_id, ".apps.googleusercontent.com")
    error_message = "Expected a Google OAuth client ID ending in .apps.googleusercontent.com."
  }
}
