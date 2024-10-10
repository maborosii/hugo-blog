+++
title = 'haskell 快速排序的相关 rust 实现'
date = 2024-10-09T10:18:27+08:00
draft = false
+++
# 背景

最近工作空闲，便重新捡起来多次欲入门而不得的技术，比如`eBPF`，`GNU C`，`cilium`，`envoy`等，这周看起了 haskell 的相关内容。

# haskell 快排

```haskell
quicksort :: (Ord a) => [a] -> [a]
quicksort [] = []
quicksort (x:xs) =
  let smallerSorted = quicksort [a | a <- xs, a <= x]   
      biggerSorted = quick [a | a <- xs, a > x]
   in smallerSorted ++ [x] ++ biggerSorted
```

***代码阐述***:

***note: haskell 中递归十分常见且重要 !!!***

第一行定义了一个名为`quicksort` 的函数，其函数签名为`quicksort :: (Ord a) => [a] -> [a]`，`::`后为具体签名，`(Ord a)`可以理解为 Rust 中的 **trait bounds**（特征约束），即泛型参数`a`被特征（或者理解为 java 和 go 中的 interface ）`Ord`所约束，该约束即要求`a`类型能**比较大小**，`=>`后面的`[a]->[a]`则为实际的函数签名，即函数入参为`a`类型的 list，返回参数也是`a`类型的 list。

剩下的 5 行内容即为函数体本身，其中`quicksort [] = []`和`quicksort (x:xs) = ...`实则为两行，在 haskell 中一般使用缩进来控制代码的行文节奏，这里就用到了**模式匹配**，可以理解为 if/else 语句，顺序不能改变，用于递归函数的边界条件以及卫语句直接返回。

重点在于`quicksort (x:xs) = ...`，这里的`(x:xs)`依然用到了模式匹配，这里的模式匹配可以理解中 python 中的序列解包，其中`x`等于`a[0]`，`xs`等于`a[1..]`。接着是 `let xx1 in xx2`，该语句实际上是一个表达式，`xx1`为定义的一系列局部变量，`xx2`即为具体表达式（返回具体的值）。`smallerSorted = quicksort [a | a <- xs, a <= x]`中`[a | a <- xs, a <= x]` 叫做 ***List Comprehension***（找不到太好的中文翻译😂），其中`a | a <- xs`理解为数学中的集合，集合`xs`中的元素`a`，而`a <= x`则是对元素`a`进行过滤，只保留小于等于`x`的元素。那么整个语义便十分清晰，遍历 list 找到大于`x`放到一个新 list 中，找到小于等于`x`的放到另一个新 list 中，并不断递归拆分的列表，直到列表为空。最终返回一个拼接之后的 list: `smallerSorted ++ [x] ++ biggerSorted`，`++`用于 list 的拼接。

代码思路看起来十分简洁，这也是函数式语言的优势，专注于"**做什么**"，而不是命令式语言中的"**怎么去做**"。快排的思路都大致相同，分而治之。但有一点不得不说是，其具体的执行效率是要低于常规的快排实现。至于选择什么样的思路去实现，取决于应用场景以及个人好恶，见仁见智。

# rust 中的快速排序

***inspired by haskell***

```rust
fn quicksort_by_hs(a: Vec<u32>) -> Vec<u32> {
    if a.is_empty() {
        return a;
    }
    let index = a[0];
    let smaller_collection = a[1..].iter().filter(|s| **s <= index).cloned().collect();
    let bigger_collection = a[1..].iter().filter(|s| **s > index).cloned().collect();
    let smaller_sorted = quicksort_by_hs(smaller_collection);
    let bigger_sorted = quicksort_by_hs(bigger_collection);
    let mut result = smaller_sorted;
    result.extend(vec![index]);
    result.extend(bigger_sorted);
    result
}
```

实现思路参考自 haskell 不多赘述。

***常规思路快速排序***

```rust
fn quicksort_universal(a: &mut Vec<u32>, start: usize, end: usize) {
    if start >= end {
        return;
    }

    let pivot = a[start];
    let mut left = start;
    let mut right = end;
    while left < right {
        while (left < right) && (a[right] > pivot) {
            right -= 1
        }
        a[left] = a[right];
        left += 1;
        while (left < right) && (a[left] <= pivot) {
            left += 1
        }
        a[right] = a[left];
        right -= 1;
    }

    a[left] = pivot;
    quicksort_universal(a, start, left - 1);
    quicksort_universal(a, right + 1, end);
}
```

***基准测试***

```plain
test bench_quicksort_by_hs     ... bench:     424,935.96 ns/iter (+/- 74,045.73)
test bench_quicksort_universal ... bench:      37,009.78 ns/iter (+/- 4,885.42)
```
