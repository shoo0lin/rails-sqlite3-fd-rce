Rails.application.routes.draw do
  post "/reflection", to: "vuln#reflection"
  post "/marshal",    to: "vuln#marshal"
end
