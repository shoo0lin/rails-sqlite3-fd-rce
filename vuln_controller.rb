require "base64"

class VulnController < ApplicationController
  # DELIBERATELY VULNERABLE — local disposable testbed only.
  def reflection
    vuln_params[:type].constantize.new(*vuln_params[:args])
    render json: { success: true }
  end

  def marshal
    deserialised = Marshal.load(Base64.decode64(vuln_params[:deserialise]))
    render json: { data: deserialised.to_s }
  end

  def vuln_params
    params.permit!
  end
end
