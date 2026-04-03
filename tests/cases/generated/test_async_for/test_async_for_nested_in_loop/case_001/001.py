async def process():
    for x in range(10):
        async for item in async_gen():
            break
