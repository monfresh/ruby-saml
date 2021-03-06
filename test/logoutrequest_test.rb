require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))

class RequestTest < Test::Unit::TestCase

  context "Logoutrequest" do
    settings = OneLogin::RubySaml::Settings.new

    should "create the deflated SAMLRequest URL parameter" do
      settings.idp_slo_target_url = "http://unauth.com/logout"
      settings.name_identifier_value = "f00f00"

      unauth_url = OneLogin::RubySaml::Logoutrequest.new.create(settings)
      assert unauth_url =~ /^http:\/\/unauth\.com\/logout\?SAMLRequest=/

      inflated = decode_saml_request_payload(unauth_url)

      assert_match /^<samlp:LogoutRequest/, inflated
    end

    should "support additional params" do

      unauth_url = OneLogin::RubySaml::Logoutrequest.new.create(settings, { :hello => nil })
      assert unauth_url =~ /&hello=$/

      unauth_url = OneLogin::RubySaml::Logoutrequest.new.create(settings, { :foo => "bar" })
      assert unauth_url =~ /&foo=bar$/
    end

    should "set sessionindex" do
      settings.idp_slo_target_url = "http://example.com"
      sessionidx = UUID.new.generate
      settings.sessionindex = sessionidx

      unauth_url = OneLogin::RubySaml::Logoutrequest.new.create(settings, { :name_id => "there" })
      inflated = decode_saml_request_payload(unauth_url)

      assert_match /<samlp:SessionIndex/, inflated
      assert_match %r(#{sessionidx}</samlp:SessionIndex>), inflated
    end

    should "set name_identifier_value" do
      settings = OneLogin::RubySaml::Settings.new
      settings.idp_slo_target_url = "http://example.com"
      settings.name_identifier_format = "transient"
      name_identifier_value = "abc123"
      settings.name_identifier_value = name_identifier_value

      unauth_url = OneLogin::RubySaml::Logoutrequest.new.create(settings, { :name_id => "there" })
      inflated = decode_saml_request_payload(unauth_url)

      assert_match /<saml:NameID/, inflated
      assert_match %r(#{name_identifier_value}</saml:NameID>), inflated
    end

    context "when the target url doesn't contain a query string" do
      should "create the SAMLRequest parameter correctly" do
        settings = OneLogin::RubySaml::Settings.new
        settings.idp_slo_target_url = "http://example.com"
        settings.name_identifier_value = "f00f00"

        unauth_url = OneLogin::RubySaml::Logoutrequest.new.create(settings)
        assert unauth_url =~ /^http:\/\/example.com\?SAMLRequest/
      end
    end

    context "when the target url contains a query string" do
      should "create the SAMLRequest parameter correctly" do
        settings = OneLogin::RubySaml::Settings.new
        settings.idp_slo_target_url = "http://example.com?field=value"
        settings.name_identifier_value = "f00f00"

        unauth_url = OneLogin::RubySaml::Logoutrequest.new.create(settings)
        assert unauth_url =~ /^http:\/\/example.com\?field=value&SAMLRequest/
      end
    end

    context "consumation of logout may need to track the transaction" do
      should "have access to the request uuid" do
        settings = OneLogin::RubySaml::Settings.new
        settings.idp_slo_target_url = "http://example.com?field=value"
        settings.name_identifier_value = "f00f00"

        unauth_req = OneLogin::RubySaml::Logoutrequest.new
        unauth_url = unauth_req.create(settings)

        inflated = decode_saml_request_payload(unauth_url)
        assert_match %r[ID='#{unauth_req.uuid}'], inflated
      end
    end

    context "when the settings indicate to sign (embebed) the logout request" do
      should "created a signed logout request" do
        settings = OneLogin::RubySaml::Settings.new
        settings.idp_slo_target_url = "http://example.com?field=value"
        settings.name_identifier_value = "f00f00"
        # sign the logout request
        settings.security[:logout_requests_signed] = true
        settings.security[:embed_sign] = true
        settings.certificate = ruby_saml_cert_text
        settings.private_key = ruby_saml_key_text

        unauth_req = OneLogin::RubySaml::Logoutrequest.new
        unauth_url = unauth_req.create(settings)

        inflated = decode_saml_request_payload(unauth_url)
        assert_match %r[<ds:SignatureValue>([a-zA-Z0-9/+=]+)</ds:SignatureValue>], inflated
      end

      should "create a signed logout request with 256 digest and signature methods" do
        settings = OneLogin::RubySaml::Settings.new
        settings.compress_request = false
        settings.idp_slo_target_url = "http://example.com?field=value"
        settings.name_identifier_value = "f00f00"
        # sign the logout request
        settings.security[:logout_requests_signed] = true
        settings.security[:embed_sign] = true
        settings.security[:signature_method] = XMLSecurity::Document::SHA256
        settings.security[:digest_method] = XMLSecurity::Document::SHA512
        settings.certificate  = ruby_saml_cert_text
        settings.private_key = ruby_saml_key_text

        params = OneLogin::RubySaml::Logoutrequest.new.create_params(settings)
        request_xml = Base64.decode64(params["SAMLRequest"])

        assert_match %r[<ds:SignatureValue>([a-zA-Z0-9/+=]+)</ds:SignatureValue>], request_xml
        request_xml =~ /<ds:SignatureMethod Algorithm='http:\/\/www.w3.org\/2001\/04\/xmldsig-more#rsa-sha256'\/>/
        request_xml =~ /<ds:DigestMethod Algorithm='http:\/\/www.w3.org\/2001\/04\/xmldsig-more#rsa-sha512'\/>/
      end
    end

    context "when the settings indicate to sign the logout request" do
      should "create a signature parameter" do
        settings = OneLogin::RubySaml::Settings.new
        settings.compress_request = false
        settings.idp_slo_target_url = "http://example.com?field=value"
        settings.name_identifier_value = "f00f00"
        settings.security[:logout_requests_signed] = true
        settings.security[:embed_sign] = false
        settings.security[:signature_method] = XMLSecurity::Document::SHA1
        settings.certificate  = ruby_saml_cert_text
        settings.private_key = ruby_saml_key_text

        params = OneLogin::RubySaml::Logoutrequest.new.create_params(settings)
        assert params['Signature']
        assert params['SigAlg'] == XMLSecurity::Document::SHA1

        # signature_method only affects the embedeed signature
        settings.security[:signature_method] = XMLSecurity::Document::SHA256
        params = OneLogin::RubySaml::Logoutrequest.new.create_params(settings)
        assert params['Signature']
        assert params['SigAlg'] == XMLSecurity::Document::SHA1
      end
    end

  end

  def decode_saml_request_payload(unauth_url)
    payload = CGI.unescape(unauth_url.split("SAMLRequest=").last)
    decoded = Base64.decode64(payload)

    zstream = Zlib::Inflate.new(-Zlib::MAX_WBITS)
    inflated = zstream.inflate(decoded)
    zstream.finish
    zstream.close
    inflated
  end

end
