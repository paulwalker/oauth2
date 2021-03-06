require 'spec_helper'

describe OAuth2::Client do
  let!(:error_value) {'invalid_token'}
  let!(:error_description_value) {'bad bad token'}
  
  subject do
    cli = OAuth2::Client.new('abc', 'def', :site => 'https://api.example.com')
    cli.connection.build do |b|
      b.adapter :test do |stub|
        stub.get('/success')      {|env| [200, {'Content-Type' => 'text/awesome'}, 'yay']}
        stub.get('/unauthorized') {|env| [401, {'Content-Type' => 'text/plain'}, MultiJson.encode(:error => error_value, :error_description => error_description_value)]}
        stub.get('/conflict')     {|env| [409, {'Content-Type' => 'text/plain'}, 'not authorized']}
        stub.get('/redirect')     {|env| [302, {'Content-Type' => 'text/plain', 'location' => '/success' }, '']}
        stub.get('/error')        {|env| [500, {}, '']}
      end
    end
    cli
  end

  describe '#initialize' do
    it 'should assign id and secret' do
      subject.id.should == 'abc'
      subject.secret.should == 'def'
    end

    it 'should assign site from the options hash' do
      subject.site.should == 'https://api.example.com'
    end

    it 'should assign Faraday::Connection#host' do
      subject.connection.host.should == 'api.example.com'
    end

    it 'should leave Faraday::Connection#ssl unset' do
      subject.connection.ssl.should == {}
    end

    it "should be able to pass parameters to the adapter, e.g. Faraday::Adapter::ActionDispatch" do
      connection = stub('connection')
      Faraday::Connection.stub(:new => connection)
      session = stub('session', :to_ary => nil)
      builder = stub('builder')
      connection.stub(:build).and_yield(builder)

      builder.should_receive(:adapter).with(:action_dispatch, session)

      OAuth2::Client.new('abc', 'def', :adapter => [:action_dispatch, session]).connection
    end

    it "defaults raise_errors to true" do
      subject.options[:raise_errors].should be_true
    end

    it "allows true/false for raise_errors option" do
      client = OAuth2::Client.new('abc', 'def', :site => 'https://api.example.com', :raise_errors => false)
      client.options[:raise_errors].should be_false
      client = OAuth2::Client.new('abc', 'def', :site => 'https://api.example.com', :raise_errors => true)
      client.options[:raise_errors].should be_true
    end

    it "allows get/post for access_token_method option" do
      client = OAuth2::Client.new('abc', 'def', :site => 'https://api.example.com', :access_token_method => :get)
      client.options[:access_token_method].should == :get
      client = OAuth2::Client.new('abc', 'def', :site => 'https://api.example.com', :access_token_method => :post)
      client.options[:access_token_method].should == :post
    end
  end

  %w(authorize access_token).each do |url_type|
    describe ":#{url_type}_url option" do
      it "should default to a path of /oauth/#{url_type}" do
        subject.send("#{url_type}_url").should == "https://api.example.com/oauth/#{url_type}"
      end

      it "should be settable via the :#{url_type}_url option" do
        subject.options[:"#{url_type}_url"] = '/oauth/custom'
        subject.send("#{url_type}_url").should == 'https://api.example.com/oauth/custom'
      end
      
      it "allows a different host than the site" do
        subject.options[:"#{url_type}_url"] = 'https://api.foo.com/oauth/custom'
        subject.send("#{url_type}_url").should == 'https://api.foo.com/oauth/custom'
      end
    end
  end

  describe "#request" do
    it "returns on a successful response" do
      response = subject.request(:get, '/success', {}, {})
      response.body.should == 'yay'
      response.status.should == 200
      response.headers.should == {'Content-Type' => 'text/awesome'}
    end

    it "follows redirects properly" do
      response = subject.request(:get, '/redirect', {}, {})
      response.body.should == 'yay'
      response.status.should == 200
      response.headers.should == {'Content-Type' => 'text/awesome'}
    end

    it "returns if raise_errors is false" do
      subject.options[:raise_errors] = false
      response = subject.request(:get, '/unauthorized', {}, {})

      response.status.should == 401
      response.headers.should == {'Content-Type' => 'text/plain'}
      response.error.should_not be_nil
    end
    
    %w(/unauthorized /conflict /error).each do |error_path|
      it "raises OAuth2::Error on error response to path #{error_path}" do
        lambda {subject.request(:get, error_path, {}, {})}.should raise_error(OAuth2::Error)
      end
    end
    
    it 'parses OAuth2 standard error response' do
      begin
        subject.request(:get, '/unauthorized', {}, {})
      rescue Exception => e
        e.code.should == error_value.to_sym
        e.description.should == error_description_value
      end
    end

    it "provides the response in the Exception" do
      begin
        subject.request(:get, '/error', {}, {})
      rescue Exception => e
        e.response.should_not be_nil
      end
    end
  end

  it '#web_server should instantiate a WebServer strategy with this client' do
    subject.web_server.should be_kind_of(OAuth2::Strategy::WebServer)
  end

  context 'with SSL options' do
    subject do
      cli = OAuth2::Client.new('abc', 'def', :site => 'https://api.example.com', :ssl => {:ca_file => 'foo.pem'})
      cli.connection.build do |b|
        b.adapter :test
      end
      cli
    end

    it 'should pass the SSL options along to Faraday::Connection#ssl' do
      subject.connection.ssl.should == {:ca_file => 'foo.pem'}
    end
  end
end
