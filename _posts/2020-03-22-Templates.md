---
layout: post
title: Constraining templates in C++
tags: c++ programming
---

In my hobby project [SimpleSTL](https://github.com/Panky-codes/SimpleSTL), I started implementing a basic version of Standard Template Library (STL) to learn modern C++ and also serve as a reference for beginners who wants to get a sneak peek into a possible implementation of STL.

I encountered something interesting while implementing the insert member function for the vector container. There are five overloads for the insert function given by the standard. The overloads that are of interest for this article are given below:
```cpp
namespace sstl {
  template<typename T>
  class vector {
...
  using const_reference = const T&;
  using const_iterator  = const T*;
  using iterator        = T*;

  iterator insert(const_iterator pos, size_t count, const_reference value); //#1
  template <typename InputIt>
  iterator insert(const_iterator pos, InputIt first, InputIt last); //#2
...
  }
}
```  
The overload #1 is used to insert a `value` for `count` number of times at position `pos` of the vector as shown in the figure below:

![Insert overload 1](/assets/templates-concepts/insert1.jpg)

The overload #2 is used to insert another container (e.g. vector, set, etc) into the vector at position `pos`. `first` and `last` are the iterators pointing to the first and the last element(not including) of the container we want to insert as shown below:

![Insert overload 2](/assets/templates-concepts/insert2.jpg)
  
Note that the variable `pos`, `first`, `last` are of type iterators. Iterators are a pointer-like object that can be incremented with ++, dereferenced with \*, and compared against another iterator with !=. The value of these iterator variables should be equal to the vector's base pointer plus the index. The picture is shown only with the index for simplicity.   

### The moment of truth!

I was writing unit tests to test overload #1 for my vector container. I wrote the code as follows:
```cpp
sstl::vector<int> vec1{1, 2, 3, 4};
auto iter = vec1.insert(vec1.cbegin() + 4, 2, 5); // index = 4, count = 2, value = 5 
```

My compiler (GCC in this case) threw an error to my function call in the unit test. In brief, the error message contained the following type deduction:
```cpp
[with InputIt = int; T = int; sstl::vector<T>::iterator = int*; sstl::vector<T>::const_iterator = const int*]
```
Ahaaaa. It takes overload #2 with template parameter `InputIt` as `int` and it tries to dereference that value, resulting in an error. The overload #2 is supposed to take iterators as a second and third argument, and not integers.

From compilers perspective it makes total sense as the values of the last two parameters in the unit test, 2 and 5 are implicitly converted to `int`s. Hence, overload #2 with `InputIt` as `int` is a better match than overload #1 with `size_t` and `const_reference` as the last two parameters.

[Cppreference](https://en.cppreference.com/w/cpp/container/vector/insert) site states the following about the insert function: "This [#2] overload only participates in overload resolution if InputIt qualifies as LegacyInputIterator, to avoid ambiguity with the overload #1". Exactly what happens here. 

I can avoid this compilation error by declaring the second parameter of the insert function to be of type `size_t`. But if this is a library that will be used by many programmers, we can't enforce the users to specify the second parameter to be of type `size_t`. The function call I wrote in my unit test is a valid code that should not result in a compilation error.

So I should somehow instruct my compiler to use overload #2 if and only if the last two parameters qualify as `LegacyInputIterator`. 
## Using std::enable_if
Initially, I didn't know how to go about giving constraints for the template parameters. Like most people, I posted this question on StackOverflow. My question was marked as **duplicate** within few minutes. Mod commented saying look at the concept called `SFINAE` (Substitution failure is not an error) and `enable_if`.

`enable_if` is used to activate certain generic code if it meets certain conditions. Think of it as a compile-time `if` condition for templates. For my problem, I need to constrain my template parameters for type `InputIt` to qualify as `LegacyInputIterator`. 

Overload #2 can be constrained with `enable_if` as follows:
```cpp
namespace sstl {
  template<typename T>
  class vector {
...
  template <typename InputIt,
            std::enable_if<
                std::is_base_of<std::input_iterator_tag,typename std::iterator_traits<
                                    InputIt>::iterator_category
                                >::value,
                bool>::type = true>
  iterator insert(const_iterator pos, InputIt first,
                    InputIt last); //#2 
...
  };
}
```
Okkk! That escalated quickly. Let me explain what it does before you start questioning yourself about learning C++. 

The `enable_if` syntax does not look idiomatic at all. If you are new to C++, like me, you might find it hard to understand the construct. As Scott Meyers points out in his book, Effective Modern C++, about the `enable_if` syntax: "the syntax is off-putting, especially if you've never seen it before". It took me some time and pestering some people in the slack channel to understand what it does. 

Before I explain how I constrained my overload #2 with `enable_if`, I will briefly touch upon the syntax of it. The definition of `std::enable_if` is as follows:
```cpp
template< bool B, class T = void >
struct enable_if;
```
We give the constraints for the template overload as the first parameter B. If the first template parameter B is true, then `enable_if` creates an alias called `type` for the second parameter T and adds this function overload to the overload set. 

When the constraint is false, we don't get an alias called `type` for T, and this function overload is removed from the overload set. They generally do this by template specialization and SFINAE, which I won't go over in this article.

Now back to the snippet of code I wrote to resolve the overload resolution problem in my code. The `enable_if` checks if the `InputIt` comes from the base class of the [std:input_iterator_tag](https://en.cppreference.com/w/cpp/iterator/iterator_tags). `std:input_iterator_tag` contains the properties of a `LegacyInputIterator` as defined by the standard. By having this in constraint in place, this generic code is enabled only if we pass iterators as the second and third parameters for function overload #2.

Now, the function call in my code snippet that I wrote for my unit test (shown below again), calls overload #1 correctly as expected. 
```cpp
sstl::vector<int> vec1{1, 2, 3, 4};
auto iter = vec1.insert(vec1.cbegin() + 4, 2, 5); // calls overload #1
```

This is one way of solving the template overload resolution problem. But is there another way of idiomatically solving this in C++?

## Concepts
With C++20, we are officially getting a feature called `Concepts` inside the standard. Concepts are named sets of requirements for the templates. They define what type of parameters the templates should accept. One of the biggest advantages of Concepts is improved error messages for users by avoiding going into the weeds of implementation. Also, the readability of the code gets better with Concepts.

I will show how we can constrain the templates using the new Concepts feature and then explain the syntax. 
```cpp
namespace sstl {

using std::iterator_traits;
using std::input_iterator_tag;

template <typename T>
  concept InputIterator = requires(T t) {
  { typename iterator_traits<T>::iterator_category{} } -> input_iterator_tag;
  };

template<typename T>
  class vector {
...
  template <InputIterator InputIt>
  iterator insert(const_iterator pos, InputIt first,
                    InputIt last); //#2 
...
  }
}
```
Initially we need to create a Concept called `InputIterator`<sup>1</sup>. The Concept has a requires clause which states that the template T's iterator category should satisfy the requirements of an `std::input_iterator_tag`. In general, the decltype of the expression inside the flower braces of the requires clause should satisfy the type constraint given after the arrow (->) symbol. 

Now we just use the newly defined Concept, `InputIterator`, when defining the template as shown in the code snippet. Notice that we are now using `InputIterator` as the template type parameter to overload #2. 

I **removed overload #1** to check the error message coming from `Concepts`. And when I did a function call as shown below:

```cpp
sstl::vector<int> vec1{1, 2, 3, 4};
auto iter = vec1.insert(vec1.cbegin() + 4, 2, 5); //Trying to call overload #1 that doesn't exist now
```
I got an error message from the compiler as follows:
```cpp
note:   constraints not satisfied
note: within template<class T> concept const bool sstl::InputIterator<T> [with T = int]
   11 | concept InputIterator = requires(T t) {
      |         ^~~~~~~~~~~~~
note:     with int t
note: the required expression typename std::iterator_traits<_Iter>::iterator_category() would be ill-formed
```
The above error message is straight to the point and indicates the problem in the first line: `constraints not satisfied`. Now I know which overload needs to be added to satisfy the function call. 

To summarize, I can constrain the template for overload #2 with `Concepts`, and it is much more readable than `enable_if` construct. It clearly shows the preconditions necessary to activate the templated code. 

## Conclusion

Concepts are long-awaited, and a powerful feature that will be in C++20. Using them makes the code with templates much more expressive and easier to debug compared to using `enable_if`. 

I have only touched the surface regarding Concepts in this post. You can try it yourself by either downloading the latest GCC compiler (clang 10.0 should arrive soon with Concepts) which has C++20 support or as always in the [compiler explorer](https://godbolt.org/) with `-fconcepts` flag.

Hope you enjoyed the article. Happy coding!

<sup>1</sup>Alternatively we could define a Concept without requires clause as follows:
```cpp
template <typename T>
concept InputIterator = std::is_base_of<std::input_iterator_tag,
                            typename std::iterator_traits<T>::iterator_category>::value;
```
