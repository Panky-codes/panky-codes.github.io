---
layout: post
title: Constraining templates in C++
---

I started my hobby project [SimpleSTL](https://github.com/Panky-codes/SimpleSTL) in which I started implementing a basic version of STL to learn Modern C++, and also serve as a reference for beginners who wants to get a sneak peek into a possible implementation of STL. 

I encountered something interesting while implementing the insert member function for the vector container. There were totally five overloads for the insert function given by the standard as follows:
```cpp
namespace SSTL
{
  template<typename T>
  class vector{
...
  iterator insert(const_iterator pos, const_reference value); //#1
  iterator insert(const_iterator pos, T&& value); //#2 
  iterator insert(const_iterator pos, size_t count, const_reference value); //#3 
  template <typename InputIt>
  iterator insert(const_iterator pos, InputIt first, InputIt last); //#4 
  iterator insert( const_iterator pos, std::initializer_list<T> ilist ); //#5
...
  }
}
```  
I was writing unit tests for my vector container, and I wrote the code below to test one of the overloads as follows:
```cpp
SSTL::vector<int> vec1{1, 2, 3, 4};
auto iter = vec1.insert(vec1.cbegin() + 4, 2, 5); //function call
```
Could you guess which overload was called? 

Well, I was expecting overload #3 to be called. To my surprise, the test code called the overload #4 which resulted in an error message from GCC. In brief, the error message contained the following type deduction:
```cpp
[with InputIt = int; T = int; SSTL::vector<T>::iterator = int*; SSTL::vector<T>::const_iterator = const int*]
```
Ahaaaa. It takes the overload #4 with template parameter `InputIt` as `int` and it tries to dereference that value, resulting in an error. 

It make total sense as the values of the last two parameters, 2 and 5 are implicitly converted to `int`s. Hence, overload 4 with `InputIt` as `int` is a better match than overload #3 with `size_t` and `const_reference` as last two parameters.

[Cppreference](https://en.cppreference.com/w/cpp/container/vector/insert) site states this: "This [#4] overload only participates in overload resolution if InputIt qualifies as LegacyInputIterator, to avoid ambiguity with the overload #3". Exactly what happens here. 

I can avoid this by specifically telling the second parameter of the insert function call to be of type `size_t`, and then it calls overload #3 as expected. But if this is a library which will be used by many programmers, we can't enforce the users to specify the second parameter to be of type `size_t`. The function call I wrote in my unit test is a valid code which should not result in a compilation error.

So I should somehow instruct my compiler to use overload #4 if and only if the last two parameters qualifies as`LegacyInputIterator`. 
## Using std::enable_if
Initially I didn't know how to go about giving constraints for the template parameters. Like everyone else, I posted this question on stackoverflow. My question was marked as **duplicate** within few minutes. Mod commented saying look at the concept called `SFINAE` (Substitution failure is not an error) and `enable_if`.

The idea of `enable_if`, as the name suggests, it **enables** the generic code **if** it meets certain conditions. I need to constrain my template parameters for type `InputIt` to qualify as `LegacyInputIterator`. 

Constraining overload #4 with `enable_if`:
```cpp
namespace SSTL
{
  template<typename T>
  class vector{
...
  template <typename InputIt,
            std::enable_if<
                std::is_base_of<std::input_iterator_tag,typename std::iterator_traits<
                                    InputIt>::iterator_category
                                >::value,
                bool>::type = true>
  iterator insert(const_iterator pos, InputIt first,
                    InputIt last); //#4 
...
  };
}

```
The `enable_if` syntax does not look idiomatic at all. If you are new to C++, like me, you might find it hard to understand the construct. As Scott Meyers said in Effective Modern C++ book about the `enable_if` syntax: "the syntax is off-putting, especially if you've never seen it before". It took me some time and pestering some people in slack channel to understand what it does. 

Before I explain how I constrained my overload #4 with `enable_if`, I will briefly touch upon the syntax of it. The definition of `std::enable_if` is as follows:
```cpp
template< bool B, class T = void >
struct enable_if;
```
If the first template parameter B is true, then `enable_if` creates an alias called `type` for the second parameter T. In essence that is all it does. 

We give the constraints for the template overload as the first parameter B. So when constraint is false, we don't get an alias called `type` for T, therefore, this template is not a good fit for the constraint B. They generally do this by template specialization which I won't go over in this article.

So if the constraint is false, we don't get an alias called type at all, yet we have it as a part of our template definition. You might ask that shouldn't it lead to build failure? That is where SFINAE comes in and says this failure is not an error, so everything works fine.

Now back to the snippet of code I wrote to resolve the overload resolution problem in my code. The `enable_if` checks if the *InputIt* comes from the base class of the [std:input_iterator_tag](https://en.cppreference.com/w/cpp/iterator/iterator_tags) which contains the properties of the LegacyInputIterator as defined by the standard. Now my test passes as this overload #4 is called only if I pass iterators as the argument. 

This is one way of solving the template overload resolution problem. But there is another way of idiomatically solving this with C++20.

## Concepts
With C++20, we are officially getting a feature called `Concepts` inside the standard. Concepts are named sets of requirements for the templates. Concepts define what type of parameters the templates should accept. One of the biggest advantages of Concepts are improved error messages for users by avoiding going into the weeds of implementation. Also the readability of the code itself is much better with Concepts.

I will show how we can constrain the templates using the new Concepts feature and then explain the syntax. 
```cpp
namespace SSTL {

using std::iterator_traits;
using std::input_iterator_tag;

template <typename T>
  concept InputIterator = requires(T t) {
  { typename iterator_traits<T>::iterator_category() } -> input_iterator_tag;
  };

template<typename T>
  class vector{
...
  template <InputIterator InputIt>
  iterator insert(const_iterator pos, InputIt first,
                    InputIt last); //#4 
...
  }
}
```
Initially we need to create a Concept called InputIterator<sup>1</sup>. The Concept has a requires clause which states that the template T's iterator category should satisfy the requirements of a `std::input_iterator_tag` to put it in layman's terms. In general, the decltype of the expression inside the flower braces of the requires clause should satisfy the type constraint given after the arrow (->) symbol. 

Now we just use the `Concept` when defining the template as shown in the example. This performs exactly the same as the previous code snippet with `enable_if` and it is much more readable. 

Bjarne Stroustrop, the founder of C++, gives the example of a sort algorithm from STL to illustrate `Concepts` at [CPPCON](https://www.youtube.com/watch?v=HddFGPTAmtU&t=1117s). Sort algorithm's template parameter defines a Concept which takes the iterator that are only sortable or else it gives a nice error message during compile time saying that the container is not sortable. I got the concept of `Concepts` (I had to do this at least once ;) ) from his talk but understood it's power only after using it. 

Hope you enjoyed the article. Happy coding!

<sup>1</sup>Alternatively we could define a concept without requires clause as follows:
```cpp
template <typename T>
concept InputIterator = std::is_base_of<std::input_iterator_tag,
                            typename std::iterator_traits<T>::iterator_category>::value;
```
