import ClaudeRingsCore

print(AccountStore().load().accounts.map(\.name))
