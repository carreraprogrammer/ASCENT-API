# boilerplate-rails-api

Rails API boilerplate with auth, authorization, and schema-driven forms.

## Permissions cache

Permissions are embedded in the JWT access token when it is issued. No extra Redis cache is implemented in this version. To extend this later, add a cache layer in the authorization domain and invalidate it when roles or permissions change.
