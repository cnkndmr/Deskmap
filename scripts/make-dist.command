#!/bin/bash
# Finder'dan çift tıklanınca: dağıtım paketini üret (build/dist/*.zip).
# Çıktı build/last-dist.log dosyasına da yazılır.
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
{
  echo "=== $(date) ==="
  make dist
  echo "=== exit: $? ==="
} 2>&1 | tee build/last-dist.log
