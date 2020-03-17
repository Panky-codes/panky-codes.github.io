---
layout: post
title: Constraining templates in C++
---

Being an embedded software engineer, I never really had a chance to use much of template metaprogramming in my C++ code. I have seen lot of talks and read a lot about the power of template metaprogramming and how it can change the way we write generic code. As my work did not allow me to do much with templates, I decided to start my own hobby project of implementing some STL myself to learn templates and also keep myself updated with the latest features from the standard.

My hobby project is called [SimpleSTL](https://github.com/Panky-codes/SimpleSTL). I encountered a weird behavior while implementing the vector container. It was when implementing insert member function. There were totally five overloads for the insert function as follows:
```cpp
namespace SSTL
{
  template<typename T>
  class vector{
...
  iterator insert(const_iterator pos, const_reference value); //#1
  iterator insert(const_iterator pos, T&& value); //#2 
  iterator insert(const_iterator pos, size_t count, const_reference value); //#3 
  template <typename input_iterator>
  iterator insert(const_iterator pos, input_iterator first, input_iterator last); //#4 
  iterator insert( const_iterator pos, std::initializer_list<T> ilist ); //#5
...
  }
}
```  
I was writing unit tests for my vector container, and in my test I wrote this code:
```cpp
SSTL::vector<int> vec1{1, 2, 3, 4};

auto iter = vec1.insert(vec1.cbegin() + 4, 2, 5);
```
Could you guess which overload was called? Well, I was expecting overload #3 to be called. As you can see, I gave the last two parameters as input iterators, so I expected #4 to be called. To my surprise, it decided to call overload #4 which resulted in an error message from GCC. The error was:
```cpp
simpleSTL/tests/../vector/vector.h:491:14:   required from ‘T* SSTL::vector<T>::insert(SSTL::vector<T>::const_iterator, 
input_iterator, input_iterator) [with input_iterator = int; T = int; SSTL::vector<T>::iterator = int*; SSTL::vector<T>::const_iterator = const int*]’
```
Ahaaaa. It takes the overload #4 with template parameter *input_iterator* as int and it tries to dereference that value resulting in an error. Cppreference site states this: "This [4] overload only participates in overload resolution if InputIt qualifies as LegacyInputIterator, to avoid ambiguity with the overload (3)". Exactly what happens here. 

I can avoid this by specifically telling the second parameter of the insert function call to be of type *size_t*. Then it calls overload 3 as expected. But if this is a library you can't enforce the users to specify the second parameter to be of type *size_t* because the call I wrote in my unit test is a valid code. So I should somehow instruct my compiler to use overload #4 if and only if the last two parameters are of type *input iterators*. 

## Using enable_if
Initially I didn't know how to go about giving constraints for the template parameters. As every sane programmer does, I posted this question on stackoverflow. And my question was marked as **duplicate** within few minutes. Mod commented saying look at the concept called SFINAE (Substitution failure is not an error) and *enable_if*.

The idea of *std::enable_if*, as the name suggests, it enables the generic code if it meets certain conditions. I need to constrain my template parameters for type *input iterators* to qualify as LegacyInputIterator. 

Constraining overload #4 with *std::enable_if*:
```cpp
namespace SSTL
{
  template<typename T>
  class vector{
...
  template <typename input_iterator,
            std::enable_if<
                std::is_base_of<std::input_iterator_tag,typename std::iterator_traits<
                                    input_iterator>::iterator_category
                                >::value,
                bool>::type = true>
  iterator insert(const_iterator pos, input_iterator first,
                    input_iterator last); //#4 
...
  };
}

```
The *enable_if* syntax does not look idiomatic at all. If you are new to C++, like me, you might find it hard to understand the construct. It took me some time and pestering some people in slack channel to understand what it does. Before I explain how I constrained my overload #4 with enable_if, I will briefly touch upon the syntax. The definition of *std::emable_if* is as follows:
```cpp
template< bool B, class T = void >
struct enable_if;
```
If the first template parameter B is true, then enable_if creates an alias called type for the second parameter T. In essence that is all it does. We give the constraints that this template needs to have as the first parameter. So when constraint is false, we don't get alias for T called type, therefore this template is not a good fit for the constraint B. 
So if the constraint is false, we don't get an alias called type at all, yet we have it as a part of our template definition. You might ask that shouldn't it lead to build failure? That is where SFINAE comes in and says this failure is not an error, so everything works fine.

Now back to the snippet of code I wrote to resolve the overload resolution problem in my code. The enable_if checks if the *input_iterator* comes from the base class of the *std:inpu_iterator_tag* which contains the properties of LegacyInputIterator as defined by the standard. Now my test passes as this overload #4 is called only if I pass iterators as the argument. 

This is one way of solving the template overload resolution problem. But there is another way of idiomatically solving this with C++20.

## Concepts
Concepts are named sets of requirements for the templates. Concepts define what type of parameters the templates should accept. And one of the biggest advantages of Concepts are improved error messages for users by avoiding going into the weeds of implementation.  

I will show how we can solve the overload resolution problem using the new Concepts feature and then explain the syntax. 
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
  template <InputIterator input_iterator>
  iterator insert(const_iterator pos, input_iterator first,
                    input_iterator last); //#4 
...
  }
}
```
Initially we need to create a Concept called InputIterator<sup>1</sup>. The concept has a requires clause which states that the template T's iterator category should satisfy the requirements of a *std::input_iterator_tag* to put it in layman's terms. In general, the expression inside the flower braces of the requires clause should satisfy the type constraint given after the arrow (->) symbol. 

Now we just use the Concept when defining the template as shown in the example. This performs exactly the same as the previous code snippet with *std::enable_if*. 



With C++20, we are officially getting Concepts inside the standard. Being an embedded software engineer, I never really had a chance to use much of template metaprogramming in my C++ code at work. As a result of that, I didn't really get why people were excited getting Concepts in C++. Bjarne Stroustrop, the founder of C++, famously gives his example for sort algorithm which takes the iterator that are only sortable or else it gives a nice error message during compile time saying that the container is not sortable. 

<sup>1</sup>Alternatively we could define a concept without requires clause as follows:
```cpp
template <typename T>
concept InputIterator = std::is_base_of<std::input_iterator_tag,
                            typename std::iterator_traits<T>::iterator_category>::value;
```
### Rejected 
In this article I will share how I encountered some C++ concepts I have never heard before. 

said in his Concepts [talk](https://www.youtube.com/watch?v=HddFGPTAmtU&t=1117s) at CPPCON

