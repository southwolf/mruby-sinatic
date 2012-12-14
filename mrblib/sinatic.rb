module Sinatic
  @http_parser = nil
  @content_type = nil
  @routes = { 'GET' => [], 'POST' => [] }
  def self.route(method, path, opts, &block)
    @routes[method] << [path, opts, block]
  end
  def self.content_type(type)
    @content_type = type
  end
  def self.do(r)
    @routes[r.method].each {|path|
      if path[0] == r.path
        param = {}
        r.body.split('&').each {|x|
          tokens = x.split('=')
          param[tokens[0]] = HTTP::URL::decode(tokens[1])
        }
        @content_type = 'text/html; charset=utf-8'
        body = path[2].call(r, param)
        return [
          "HTTP/1.0 200 OK",
          "Content-Type: #{@content_type}",
          "Content-Length: #{body.size}",
          "", ""].join("\r\n") + body
      end
    }
    if r.method == 'GET'
      f = nil
      begin
        f = UV::FS::open("static#{r.path}", UV::FS::O_RDONLY|UV::FS::O_BINARY, UV::FS::S_IREAD)
        body = ''
        while (read = f.read()).size > 0
          body += read
        end
        return [
            "HTTP/1.0 200 OK",
            "Content-Type: application/octet-stream; charset=utf-8",
            "Content-Length: #{body.size}",
            "", ""].join("\r\n") + body
      rescue RuntimeError
      ensure
        f.close if f
      end
    end
    return "HTTP/1.0 404 Not Found\r\nContent-Length: 10\r\n\r\nNot Found\n"
  end
  def self.run()
    h = HTTP::Parser.new()
    s = UV::TCP.new()
    s.bind(UV::ip4_addr('127.0.0.1', 8888))
    s.listen(2000) {|x|
      return if x != 0
      c = s.accept()
      c.read_start {|b|
        return unless b
        h.parse_request(b) {|r|
          i = b.index("\r\n\r\n") + 4
          r.body = b.slice(i, b.size - i)
          c.write(::Sinatic.do(r)) {|x|
            c.close() if c
            c = nil
            #GC.start
          }
        }
      }
    }
    UV::run()
  end
end

module Kernel
  def get(path, opts={}, &block)
    ::Sinatic.route 'GET', path, opts, &block
  end
  def post(path, opts={}, &block)
    ::Sinatic.route 'POST', path, opts, &block
  end
  def content_type(type)
    ::Sinatic.content_type type
  end
end

# vim: set fdm=marker:
