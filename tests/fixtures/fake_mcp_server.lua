-- minimal stdio JSON-RPC echo server (answers every request that has an id)
io.stdout:setvbuf("no")
for line in io.lines() do
  local id = line:match('"id":(%d+)')
  if id then
    io.write(
      '{"jsonrpc":"2.0","id":'
        .. id
        .. ',"result":{"serverInfo":{"name":"fake","version":"1"},"capabilities":{},"tools":[{"name":"echo"}]}}\n'
    )
  end
end
io.stderr:write("fake server saw EOF\n")
