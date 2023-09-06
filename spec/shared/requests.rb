shared_examples "Requests" do |host|
  let(:host) { host }

  before do
    subject.auto_manage_tokens = false
  end

  it 'should load config from a file' do
    subject.user.id.should == 'john.foo'
    subject.user.access_token.should == 'aatoken'
    subject.user.refresh_token.should == 'rrtoken'
  end

  it 'should have a user object wrapping the config' do
    subject.config['something'] = 'some value'

    subject.user.something.should == 'some value'
  end

  describe '#log_in' do
    let(:response_json) { JSON.generate(
      "did": "did:plc:abracadabra",
      "accessJwt": "aaaa1234",
      "refreshJwt": "rrrr1234"
    )}

    before do
      stub_request(:post, "https://#{host}/xrpc/com.atproto.server.createSession")
        .to_return(body: response_json)
    end

    it 'should make a request to com.atproto.server.createSession' do
      subject.log_in

      WebMock.should have_requested(:post, "https://#{host}/xrpc/com.atproto.server.createSession")
        .once.with(body: %({"identifier":"john.foo","password":"hunter2"}))
    end

    [true, false, nil, :undefined, 'wtf'].each do |v|
      context "with send_auth_headers set to #{v.inspect}" do
        it 'should not set authentication header' do
          subject.send_auth_headers = v unless v == :undefined
          subject.log_in

          WebMock.should have_requested(:post, "https://#{host}/xrpc/com.atproto.server.createSession")
          WebMock.should_not have_requested(:post, "https://#{host}/xrpc/com.atproto.server.createSession")
            .with(headers: { 'Authorization' => /.*/ })
        end
      end
    end

    it "should save user's DID" do
      subject.log_in

      reloaded_config['did'].should == "did:plc:abracadabra"
    end

    it "should update the tokens in the config file" do
      subject.log_in

      reloaded_config['access_token'].should == 'aaaa1234'
      reloaded_config['refresh_token'].should == 'rrrr1234'
    end

    it 'should return the response json' do
      subject.log_in.should == JSON.parse(response_json)
    end
  end

  describe '#perform_token_refresh' do
    let(:response_json) { JSON.generate(
      "accessJwt": "aaaa1234",
      "refreshJwt": "rrrr1234"      
    )}

    before do
      stub_request(:post, "https://#{host}/xrpc/com.atproto.server.refreshSession")
        .to_return(body: response_json)
    end

    it 'should make a request to com.atproto.server.refreshSession' do
      subject.perform_token_refresh

      WebMock.should have_requested(:post, "https://#{host}/xrpc/com.atproto.server.refreshSession")
        .once.with(body: '')
    end

    [true, false, nil, :undefined, 'wtf'].each do |v|
      context "with send_auth_headers set to #{v.inspect}" do
        it 'should authenticate with the refresh token' do
          subject.send_auth_headers = v unless v == :undefined
          subject.perform_token_refresh

          WebMock.should have_requested(:post, "https://#{host}/xrpc/com.atproto.server.refreshSession")
            .once.with(headers: { 'Authorization' => 'Bearer rrtoken' })
        end
      end
    end

    it "should update the tokens in the config file" do
      subject.perform_token_refresh

      reloaded_config['access_token'].should == 'aaaa1234'
      reloaded_config['refresh_token'].should == 'rrrr1234'
    end

    it 'should return the response json' do
      subject.perform_token_refresh.should == JSON.parse(response_json)
    end
  end

  describe '#get_request' do
    before do
      stub_request(:get, %r(https://#{host}/xrpc/com.example.service.getStuff(\?.*)?))
        .to_return(body: '{ "result": 123 }')
    end

    it 'should make a request to the given XRPC endpoint' do
      subject.get_request('com.example.service.getStuff')

      WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
    end

    it 'should return parsed JSON' do
      result = subject.get_request('com.example.service.getStuff')

      result.should == { 'result' => 123 }
    end

    context 'with params' do
      it 'should append params to the URL' do
        subject.get_request('com.example.service.getStuff', { repo: 'whitehouse.gov', limit: 80 })

        WebMock.should have_requested(:get,
         "https://#{host}/xrpc/com.example.service.getStuff?repo=whitehouse.gov&limit=80").once
      end
    end

    context 'with nil params' do
      it 'should not append anything to the URL' do
        subject.get_request('com.example.service.getStuff', nil)

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
      end
    end

    context 'with an array passed as param' do
      it 'should append one copy of the param for each item' do
        subject.get_request('com.example.service.getStuff', { profiles: ['john.foo', 'spam.zip'], reposts: true })

        WebMock.should have_requested(:get,
         "https://#{host}/xrpc/com.example.service.getStuff?profiles=john.foo&profiles=spam.zip&reposts=true").once
      end
    end

    [true, false, nil, :undefined, 'wtf'].each do |v|
      context "with send_auth_headers set to #{v.inspect}" do
        before do
          subject.send_auth_headers = v unless v == :undefined
        end

        context 'with an explicit auth token' do
          it 'should pass the token in the header' do
            subject.get_request('com.example.service.getStuff', auth: 'token777')

            WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
              .with(headers: { 'Authorization' => 'Bearer token777' })
          end
        end

        context 'with auth = true' do
          it 'should use the access token' do
            subject.get_request('com.example.service.getStuff', auth: true)

            WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
              .with(headers: { 'Authorization' => 'Bearer aatoken' })
          end
        end

        context 'with auth = false' do
          it 'should not set the authorization header' do
            subject.get_request('com.example.service.getStuff', auth: false)

            WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
            WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff")
              .with(headers: { 'Authorization' => /.*/ })
          end
        end

        context 'with auth = nil' do
          it 'should not set the authorization header' do
            subject.get_request('com.example.service.getStuff', auth: nil)

            WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
            WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff")
              .with(headers: { 'Authorization' => /.*/ })
          end
        end
      end
    end

    context 'without an auth parameter' do
      it 'should use the access token if send_auth_headers is true' do
        subject.send_auth_headers = true
        subject.get_request('com.example.service.getStuff')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
      end

      it 'should use the access token if send_auth_headers is not set' do
        subject.get_request('com.example.service.getStuff')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
      end

      it 'should use the access token if send_auth_headers is set to a truthy value' do
        subject.send_auth_headers = 'wtf'
        subject.get_request('com.example.service.getStuff')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
      end

      it 'should should not set the authorization header if send_auth_headers is false' do
        subject.send_auth_headers = false
        subject.get_request('com.example.service.getStuff')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
        WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff")
          .with(headers: { 'Authorization' => /.*/ })
      end

      it 'should should not set the authorization header if send_auth_headers is nil' do
        subject.send_auth_headers = nil
        subject.get_request('com.example.service.getStuff')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff").once
        WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.getStuff")
          .with(headers: { 'Authorization' => /.*/ })
      end
    end
  end

  describe '#post_request' do
    let(:response) {{ body: '{ "result": "ok" }' }}

    before do
      stub_request(:post, "https://#{host}/xrpc/com.example.service.doStuff").to_return(response)
    end

    it 'should make a request to the given XRPC endpoint' do
      subject.post_request('com.example.service.doStuff')

      WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
    end

    it 'should return parsed JSON' do
      result = subject.post_request('com.example.service.doStuff')

      result.should == { 'result' => 'ok' }
    end

    it 'should set content type to application/json' do
      subject.post_request('com.example.service.doStuff')

      WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
        .with(headers: { 'Content-Type' => 'application/json' })
    end

    [true, false, nil, :undefined, 'wtf'].each do |v|
      context "with send_auth_headers set to #{v.inspect}" do
        before do
          subject.send_auth_headers = v unless v == :undefined
        end

        context 'with an explicit auth token' do
          it 'should pass the token in the header' do
            subject.post_request('com.example.service.doStuff', auth: 'qwerty99')

            WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
              .with(headers: { 'Authorization' => 'Bearer qwerty99' })
          end
        end

        context 'with auth = false' do
          it 'should not set the authorization header' do
            subject.post_request('com.example.service.doStuff', auth: false)

            WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
            WebMock.should_not have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff")
              .with(headers: { 'Authorization' => /.*/ })
          end
        end

        context 'with auth = nil' do
          it 'should not set the authorization header' do
            subject.post_request('com.example.service.doStuff', auth: nil)

            WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
            WebMock.should_not have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff")
              .with(headers: { 'Authorization' => /.*/ })
          end
        end
      end
    end

    context 'without an auth parameter' do
      it 'should use the access token if send_auth_headers is true' do
        subject.send_auth_headers = true
        subject.post_request('com.example.service.doStuff')

        WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
      end

      it 'should use the access token if send_auth_headers is not set' do
        subject.post_request('com.example.service.doStuff')

        WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
      end

      it 'should use the access token if send_auth_headers is set to a truthy value' do
        subject.send_auth_headers = 'wtf'
        subject.post_request('com.example.service.doStuff')

        WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
      end

      it 'should not set the authorization header if send_auth_headers is false' do
        subject.send_auth_headers = false
        subject.post_request('com.example.service.doStuff')

        WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
        WebMock.should_not have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff")
          .with(headers: { 'Authorization' => /.*/ })
      end

      it 'should not set the authorization header if send_auth_headers is nil' do
        subject.send_auth_headers = nil
        subject.post_request('com.example.service.doStuff')

        WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
        WebMock.should_not have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff")
          .with(headers: { 'Authorization' => /.*/ })
      end
    end

    context 'if params are passed' do
      it 'should encode them as JSON in the body' do
        data = { repo: 'kate.dev', limit: 40, fields: ['name', 'posts'] }
        subject.post_request('com.example.service.doStuff', data)

        WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
          .with(body: JSON.generate(data))
      end
    end

    context 'if params are not passed' do
      it 'should send an empty body' do
        subject.post_request('com.example.service.doStuff')

        WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
          .with(body: '')
      end
    end

    context 'if params are an explicit nil' do
      it 'should send an empty body' do
        subject.post_request('com.example.service.doStuff', nil)

        WebMock.should have_requested(:post, "https://#{host}/xrpc/com.example.service.doStuff").once
          .with(body: '')
      end
    end

    context 'if the response has a 4xx status' do
      let(:response) {{ body: '{ "error": "message" }', status: 403 }}

      it 'should raise an error' do
        expect { subject.post_request('com.example.service.doStuff') }.to raise_error(Minisky::ClientErrorResponse)
      end
    end
  end

  describe '#fetch_all' do
    context 'when one page of items is returned' do
      before do
        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll")
          .to_return(body: '{ "items": ["one", "two", "three"] }')
      end

      it 'should make one request to the given endpoint' do
        subject.fetch_all('com.example.service.fetchAll', field: 'items')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
      end

      it 'should return the parsed items' do
        result = subject.fetch_all('com.example.service.fetchAll', field: 'items')
        result.should == ["one", "two", "three"]
      end
    end

    context 'when more than one page of items is returned' do
      before do
        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll")
          .to_return(body: '{ "items": ["one", "two", "three"], "cursor": "ccc111" }')

        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc111")
          .to_return(body: '{ "items": ["four", "five"] }')
      end

      it 'should make multiple requests, passing the last cursor' do
        subject.fetch_all('com.example.service.fetchAll', field: 'items')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc111").once
      end

      it 'should return all the parsed items collected from the responses' do
        result = subject.fetch_all('com.example.service.fetchAll', field: 'items')
        result.should == ["one", "two", "three", "four", "five"]
      end
    end

    context 'when params are passed' do
      before do
        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll?type=post")
          .to_return(body: '{ "items": ["one", "two", "three"], "cursor": "ccc222" }')

        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll?type=post&cursor=ccc222")
          .to_return(body: '{ "items": ["four", "five"] }')
      end

      it 'should add the params to the url' do
        subject.fetch_all('com.example.service.fetchAll', { type: 'post' }, field: 'items')

        WebMock.should have_requested(:get,
          "https://#{host}/xrpc/com.example.service.fetchAll?type=post").once
        WebMock.should have_requested(:get,
          "https://#{host}/xrpc/com.example.service.fetchAll?type=post&cursor=ccc222").once
      end
    end

    context 'when params are an explicit nil' do
      before do
        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll")
          .to_return(body: '{ "items": ["one", "two", "three"], "cursor": "ccc222" }')

        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc222")
          .to_return(body: '{ "items": ["four", "five"] }')
      end

      it 'should not add anything to the url' do
        subject.fetch_all('com.example.service.fetchAll', nil, field: 'items')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc222").once
      end
    end

    [true, false, nil, :undefined, 'wtf'].each do |v|
      context "with send_auth_headers set to #{v.inspect}" do
        before do
          stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll")
            .to_return(body: '{ "items": ["one", "two", "three"], "cursor": "ccc333" }')

          stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc333")
            .to_return(body: '{ "items": ["four", "five"] }')

          subject.send_auth_headers = v unless v == :undefined
        end

        context 'with an explicit token' do
          it 'should pass the token in the header' do
            subject.fetch_all('com.example.service.fetchAll', auth: 'XXXX', field: 'items')

            WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
              .with(headers: { 'Authorization' => 'Bearer XXXX' })
            WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc333").once
              .with(headers: { 'Authorization' => 'Bearer XXXX' })
          end
        end

        context 'with auth = false' do
          it 'should not add an authentication header' do
            subject.fetch_all('com.example.service.fetchAll', field: 'items', auth: false)

            WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
            WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc333").once
            WebMock.should_not have_requested(:get, %r(https://#{host}/xrpc/com.example.service.fetchAll))
              .with(headers: { 'Authorization' => /.*/ })
          end
        end

        context 'with auth = nil' do
          it 'should not add an authentication header' do
            subject.fetch_all('com.example.service.fetchAll', field: 'items', auth: nil)

            WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
            WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc333").once
            WebMock.should_not have_requested(:get, %r(https://#{host}/xrpc/com.example.service.fetchAll))
              .with(headers: { 'Authorization' => /.*/ })
          end
        end
      end
    end

    context "without an auth parameter" do
      before do
        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll")
          .to_return(body: '{ "items": ["one", "two", "three"], "cursor": "ccc333" }')

        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc333")
          .to_return(body: '{ "items": ["four", "five"] }')
      end

      it 'should use the access token if send_auth_headers is true' do
        subject.send_auth_headers = true
        subject.fetch_all('com.example.service.fetchAll', field: 'items')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc333").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
      end

      it 'should use the access token if send_auth_headers is not set' do
        subject.fetch_all('com.example.service.fetchAll', field: 'items')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc333").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
      end

      it 'should use the access token if send_auth_headers is set to a truthy value' do
        subject.send_auth_headers = 'wtf'
        subject.fetch_all('com.example.service.fetchAll', field: 'items')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc333").once
          .with(headers: { 'Authorization' => 'Bearer aatoken' })
      end

      it 'should not add an authentication header if send_auth_headers is false' do
        subject.send_auth_headers = false
        subject.fetch_all('com.example.service.fetchAll', field: 'items')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc333").once
        WebMock.should_not have_requested(:get, %r(https://#{host}/xrpc/com.example.service.fetchAll))
          .with(headers: { 'Authorization' => /.*/ })
      end

      it 'should not add an authentication header if send_auth_headers is nil' do
        subject.send_auth_headers = nil
        subject.fetch_all('com.example.service.fetchAll', field: 'items')

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=ccc333").once
        WebMock.should_not have_requested(:get, %r(https://#{host}/xrpc/com.example.service.fetchAll))
          .with(headers: { 'Authorization' => /.*/ })
      end
    end

    context 'when break condition is passed' do
      before do
        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll")
          .to_return(body: '{ "items": ["one", "two", "three"], "cursor": "page1" }')

        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page1")
          .to_return(body: '{ "items": ["four", "five"], "cursor": "page2" }')

        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page2")
          .to_return(body: '{ "items": ["six"] }')
      end

      it 'should stop when a matching item is found' do
        subject.fetch_all('com.example.service.fetchAll', field: 'items', break_when: ->(x) { x =~ /u/ })

        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
        WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page1").once
        WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page2")
      end

      it 'should filter out matching items from the response' do
        result = subject.fetch_all('com.example.service.fetchAll', field: 'items', break_when: ->(x) { x =~ /u/ })
        result.should == ["one", "two", "three", "five"]
      end
    end

    context 'when max pages limit is passed' do
      before do
        stub_request(:get, %r(https://#{host}/xrpc/com.example.service.fetchAll(\?.*)?))
          .to_return { |req|
            params = req.uri.query_values || {}
            page = params['cursor'].to_s.gsub(/page/, '').to_i
            { body: JSON.generate({ items: ["item#{page}"], cursor: "page#{page + 1}" }) }
          }
      end

      context 'and break_when is not passed' do
        it 'should stop at n-th page' do
          subject.fetch_all('com.example.service.fetchAll', field: 'items', max_pages: 5)

          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page1").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page2").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page3").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page4").once
          WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page5")
        end

        it 'should collect all items' do
          result = subject.fetch_all('com.example.service.fetchAll', field: 'items', max_pages: 5)
          result.should == ["item0", "item1", "item2", "item3", "item4"]
        end
      end

      context 'and break_when matches earlier' do
        it 'should stop at the page where break_when matches' do
          subject.fetch_all('com.example.service.fetchAll', field: 'items', max_pages: 5,
            break_when: ->(x) { x =~ /3/ })

          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page1").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page2").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page3").once
          WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page4")
          WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page5")
        end

        it 'should exclude items that matched break_when' do
          result = subject.fetch_all('com.example.service.fetchAll', field: 'items', max_pages: 5,
            break_when: ->(x) { x =~ /3/ })

          result.should == ["item0", "item1", "item2"]
        end
      end

      context "and break_when doesn't match earlier" do
        it 'should stop at the n-th page' do
          subject.fetch_all('com.example.service.fetchAll', field: 'items', max_pages: 6,
            break_when: ->(x) { x =~ /8/ })

          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page1").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page2").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page3").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page4").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page5").once
          WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page6")
          WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page7")
        end

        it 'should include all items up to n-th page' do
          result = subject.fetch_all('com.example.service.fetchAll', field: 'items', max_pages: 6,
            break_when: ->(x) { x =~ /8/ })

          result.should == ["item0", "item1", "item2", "item3", "item4", "item5"]
        end
      end

      context "and break_when matches on the last page" do
        it 'should stop at the n-th page' do
          subject.fetch_all('com.example.service.fetchAll', field: 'items', max_pages: 6,
            break_when: ->(x) { x =~ /5/ })

          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page1").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page2").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page3").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page4").once
          WebMock.should have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page5").once
          WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page6")
          WebMock.should_not have_requested(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page7")
        end

        it 'should exclude the items matching on the last page' do
          result = subject.fetch_all('com.example.service.fetchAll', field: 'items', max_pages: 6,
            break_when: ->(x) { x =~ /5/ })

          result.should == ["item0", "item1", "item2", "item3", "item4"]
        end
      end
    end

    describe 'progress param' do
      before do
        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll")
          .to_return(body: '{ "items": ["one"], "cursor": "page1" }')

        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page1")
          .to_return(body: '{ "items": ["two"], "cursor": "page2" }')

        stub_request(:get, "https://#{host}/xrpc/com.example.service.fetchAll?cursor=page2")
          .to_return(body: '{ "items": ["three"] }')
      end

      context 'when it is passed' do
        it 'should print the progress character for each request' do
          expect {
            subject.fetch_all('com.example.service.fetchAll', field: 'items', progress: '-=')
          }.to output('-=-=-=').to_stdout
        end
      end

      context 'when it is not passed' do
        it 'should not print anything' do
          expect {
            subject.fetch_all('com.example.service.fetchAll', field: 'items')
          }.to output('').to_stdout
        end
      end

      context 'when it is passed and a default is set' do
        it 'should use the param version' do
          subject.default_progress = '@'

          expect {
            subject.fetch_all('com.example.service.fetchAll', field: 'items', progress: '#')
          }.to output('###').to_stdout
        end
      end

      context 'when it is not passed and a default is set' do
        it 'should use the default version' do
          subject.default_progress = '$'

          expect {
            subject.fetch_all('com.example.service.fetchAll', field: 'items')
          }.to output('$$$').to_stdout
        end
      end

      context 'when default is set and nil is passed' do
        it 'should not output anything' do
          subject.default_progress = '$'

          expect {
            subject.fetch_all('com.example.service.fetchAll', field: 'items', progress: nil)
          }.to output('').to_stdout
        end
      end

      context 'when default is set and false is passed' do
        it 'should not output anything' do
          subject.default_progress = '$'

          expect {
            subject.fetch_all('com.example.service.fetchAll', field: 'items', progress: false)
          }.to output('').to_stdout
        end
      end
    end
  end
end