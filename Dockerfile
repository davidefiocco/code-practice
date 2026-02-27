FROM alpine:3.20

RUN apk add --no-cache neovim python3 git sqlite-dev

WORKDIR /plugin
COPY . .

RUN mkdir -p /root/.local/share/nvim/code-practice

RUN nvim --headless -u test/install_deps.lua \
    -c "Lazy sync" -c "sleep 15" -c "qa!" 2>&1

RUN python3 test/seed_db.py \
    /root/.local/share/nvim/code-practice/exercises.db \
    test/example_exercises.json

CMD ["nvim", "--headless", "-u", "dev/init.lua", "-l", "test/test_flow.lua"]
