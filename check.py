# scripts/check.py
def add(a, b):
    return a + b

if __name__ == "__main__":
    result = add(2, 3)
    assert result == 5, "Math is broken!"
    print("Test passed: 2 + 3 == 5")
